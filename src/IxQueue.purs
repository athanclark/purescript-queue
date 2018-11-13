module IxQueue
  ( module Queue.Types
  , IxQueue (..)
  , new, put, putMany
  , broadcast, broadcastMany
  , broadcastExcept, broadcastManyExcept
  , on, once, draw
  , readBroadcast, read, takeBroadcast, take
  , del, clear, drain
  ) where

import Queue.Types (kind SCOPE, READ, WRITE, class QueueScope, Handler)

import Prelude
import Foreign.Object (Object)
import Foreign.Object as Object
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Foldable (foldr)
import Data.FoldableWithIndex (traverseWithIndex_)
import Data.Traversable (class Traversable, traverse_)
import Data.Array as Array
import Data.Array (head) as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty (singleton, toArray) as Array
import Data.Array.ST (push, pushAll, splice, thaw, unsafeFreeze, withArray) as Array
import Data.NonEmpty (NonEmpty (..))
import Control.Monad.ST (ST)
import Control.Monad.ST (run) as ST
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Ref (Ref)
import Effect.Ref as Ref


newtype IxQueue (rw :: # SCOPE) a = IxQueue
  { individual :: Ref (Object (Either (NonEmptyArray a) (Handler a)))
  , broadcast  :: Ref (Array a)
  }


new :: forall a. Effect (IxQueue (read :: READ, write :: WRITE) a)
new = do
  individual <- Ref.new Object.empty
  b <- Ref.new []
  pure (IxQueue {individual,broadcast:b})


instance queueScopeIxQueue :: QueueScope IxQueue where
  readOnly     (IxQueue xs) = IxQueue xs
  allowWriting (IxQueue xs) = IxQueue xs
  writeOnly    (IxQueue xs) = IxQueue xs
  allowReading (IxQueue xs) = IxQueue xs

put :: forall a rw. IxQueue (write :: WRITE | rw) a -> String -> a -> Effect Unit
put q k x = putMany q k (NonEmpty x [])


-- | Application policy is such that the inputs are stored in the named handler's "pending" values, if a handler isn't registered.
--   If so, apply the handler uniformly across the values, according to `t`'s `Traversable` instance.
putMany :: forall a rw
         . IxQueue (write :: WRITE | rw) a
        -> String
        -> NonEmptyArray a
        -> Effect Unit
putMany (IxQueue {individual}) k xss = do
  hs <- Ref.read individual
  case Object.lookup k hs of
    Nothing ->
      -- store locally pending values
      let obj = ST.run go
          go = do
            o <- Object.thawST hs
            _ <- Object.poke k (Left (Array.toArray xss)) o
            Object.freezeST o
      in  Ref.write obj individual
    Just ePH -> case ePH of
      -- append locally pending values
      Left pending ->
        let obj = ST.run go
            go = do
              pending' <- Array.withArray (Array.pushAll (Array.toArray xss)) pending
              o <- Object.thawST hs
              _ <- Object.poke k (Left pending') o
              Object.freezeST o
        in  Ref.write obj individual
      -- suit handlers
      Right h -> traverse_ h xss



broadcast :: forall a rw. IxQueue (write :: WRITE | rw) a -> a -> Effect Unit
broadcast q x = broadcastMany q (Array.singleton x)


broadcastMany :: forall a rw. IxQueue (write :: WRITE | rw) a -> NonEmptyArray a -> Effect Unit
broadcastMany q xs = broadcastManyExcept q [] xs


broadcastExcept :: forall a rw. IxQueue (write :: WRITE | rw) a -> Array String -> a -> Effect Unit
broadcastExcept q ex x = broadcastManyExcept q ex (Array.singleton x)


-- | Application policy is such that the inputs will be applied uniformly to all handlers, sorted by their keyed ordering, per input - directed by `t`'s `Traversable` instance.
--   Values are stored globally iff. there are no handlers, and locally if there's already pending values.
broadcastManyExcept :: forall a rw
                     . IxQueue (write :: WRITE | rw) a
                    -> Array String
                    -> NonEmptyArray a -> Effect Unit
broadcastManyExcept (IxQueue {individual,broadcast:b}) excluding xss = do
  hs <- Ref.read individual

  let hasHandler :: Either (NonEmptyArray a) (Handler a) -> Boolean
      hasHandler (Right _) = true
      hasHandler _ = false

  if Object.isEmpty (Object.filter hasHandler hs)
    then void (Ref.modify (\pending -> pending <> xsAsArray') b)
    else
      let go :: a -> Effect Unit
          go x = do
            hs' <- Ref.read individual
            let go' :: String -> Either (NonEmptyArray a) (Handler a) -> Effect Unit
                go' k ePH =
                  when (k `Array.notElem` excluding) $ case ePH of
                    Left pending -> Ref.write (Object.insert k (Left (appendNonEmpty pending (NonEmpty x []))) hs') individual
                    Right h -> h x
            traverseWithIndex_ go' hs'
      in  traverse_ go xss
  where
    xsAsArray :: NonEmpty Array a
    xsAsArray = case xss of
      NonEmpty x xs -> NonEmpty x (foldr Array.cons [] xs)
    xsAsArray' :: Array a
    xsAsArray' = case xsAsArray of
      NonEmpty x xs -> Array.cons x xs


-- | Application policy is such that the globally pending inputs will be extracted and applied to the handler, if they exist, and likewise to the locally pending inputs,
--   before registering the handler under the name.
on :: forall a rw. IxQueue (read :: READ | rw) a -> String -> Handler a -> Effect Unit
on (IxQueue {individual,broadcast:b}) k f = do
  bs <- Ref.read b
  -- consume pending global values
  unless (Array.null bs) $ do
    Ref.write [] b
    traverse_ f bs
  hs <- Ref.read individual
  -- consume pending local values
  case Object.lookup k hs of
    Nothing -> pure unit
    Just ePH -> case ePH of
      Left pending -> traverse_ f pending
      Right _ -> pure unit
  Ref.write (Object.insert k (Right f) hs) individual


once :: forall a rw. IxQueue (read :: READ | rw) a -> String -> Handler a -> Effect Unit
once q@(IxQueue {broadcast:b,individual}) k f = do
  bs <- Ref.read b
  case Array.uncons bs of
    Just {head,tail} -> do
      Ref.write tail b
      f head
    Nothing -> do
      hs <- Ref.read individual
      case Object.lookup k hs of
        Just (Left (NonEmpty x xs)) -> do
          case Array.uncons xs of
            Nothing ->
              Ref.write (Object.delete k hs) individual
            Just {head,tail} ->
              Ref.write (Object.insert k (Left (NonEmpty head tail)) hs) individual
          f x
        _ ->
          let f' x = do
                Ref.write (Object.delete k hs) individual
                f x
          in  Ref.write (Object.insert k (Right f') hs) individual


draw :: forall rw a. IxQueue (read :: READ | rw) a -> String -> Aff a
draw q k = makeAff \resolve -> do
  once q k (resolve <<< Right)
  pure nonCanceler


read :: forall a rw. IxQueue rw a -> String -> Effect (Array a)
read (IxQueue {individual}) k = do
  hs <- Ref.read individual
  case Object.lookup k hs of
    Nothing -> pure []
    Just ePH -> case ePH of
      Left (NonEmpty x xs) -> pure (Array.cons x xs)
      Right _ -> pure []


readBroadcast :: forall a rw. IxQueue rw a -> Effect (Array a)
readBroadcast (IxQueue {broadcast:b}) = Ref.read b


-- | Removes locally pending inputs for a specific key
take :: forall a rw. IxQueue (write :: WRITE | rw) a -> String -> Effect (Array a)
take (IxQueue {individual}) k = do
  hs <- Ref.read individual
  case Object.lookup k hs of
    Nothing -> pure []
    Just ePH -> case ePH of
      Left (NonEmpty x xs) -> do
        Ref.write (Object.delete k hs) individual
        pure (Array.cons x xs)
      Right _ -> pure []


-- | Removes only the globally pending inputs
takeBroadcast :: forall a rw. IxQueue (write :: WRITE | rw) a -> Effect (Array a)
takeBroadcast (IxQueue {broadcast:b}) = do
  xs <- Ref.read b
  Ref.write [] b
  pure xs


-- | Unregisters a handler, returns whether one existed
del :: forall a rw. IxQueue (read :: READ | rw) a -> String -> Effect Boolean
del (IxQueue {individual}) k = do
  hs <- Ref.read individual
  case Object.lookup k hs of
    Nothing -> pure false
    Just ePH -> case ePH of
      Left pending -> pure false
      Right _ -> do
        Ref.write (Object.delete k hs) individual
        pure true


-- | Removes all handlers, but preserves pending data
clear :: forall a rw. IxQueue (read :: READ | rw) a -> Effect Unit
clear q@(IxQueue{individual}) = do
  hs <- Ref.read individual
  traverse_ (\k -> unit <$ del q k) (Object.keys hs)


-- | Applies a nullary named handler, to remove any globally pending data
drain :: forall a rw. IxQueue (read :: READ | rw) a -> String -> Effect Unit
drain q k = on q k \_ -> pure unit




appendNonEmpty :: forall a. NonEmpty Array a -> NonEmpty Array a -> NonEmpty Array a
appendNonEmpty (NonEmpty x xs) (NonEmpty y ys) = NonEmpty x (xs <> [y] <> ys)
