module IxQueue
  ( module Queue.Types
  , IxQueue (..)
  , newIxQueue, putIxQueue, putManyIxQueue
  , broadcastIxQueue, broadcastManyIxQueue
  , broadcastExceptIxQueue, broadcastManyExceptIxQueue
  , onIxQueue, onceIxQueue, drawIxQueue
  , readBroadcastIxQueue, readIxQueue, takeBroadcastIxQueue, takeIxQueue
  , delIxQueue, clearIxQueue, drainIxQueue
  ) where

import Queue.Types (kind SCOPE, READ, WRITE, class QueueScope, Handler)

import Prelude
import Data.StrMap (StrMap)
import Data.StrMap as StrMap
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Foldable (foldr)
import Data.Traversable (class Traversable, traverse_)
import Data.TraversableWithIndex (traverseWithIndex)
import Data.Array as Array
import Data.NonEmpty (NonEmpty (..))
import Control.Monad.Aff (Aff, makeAff, nonCanceler)
import Control.Monad.Eff (Eff, kind Effect)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef, modifyRef)


newtype IxQueue (rw :: # SCOPE) (eff :: # Effect) a = IxQueue
  { individual :: Ref (StrMap (Either (NonEmpty Array a) (Handler eff a)))
  , broadcast  :: Ref (Array a)
  }


newIxQueue :: forall eff a. Eff (ref :: REF | eff) (IxQueue (read :: READ, write :: WRITE) (ref :: REF | eff) a)
newIxQueue = do
  individual <- newRef StrMap.empty
  broadcast <- newRef []
  pure (IxQueue {individual,broadcast})


instance queueScopeIxQueue :: QueueScope IxQueue where
  readOnly     (IxQueue xs) = IxQueue xs
  allowWriting (IxQueue xs) = IxQueue xs
  writeOnly    (IxQueue xs) = IxQueue xs
  allowReading (IxQueue xs) = IxQueue xs

putIxQueue :: forall eff a rw. IxQueue (write :: WRITE | rw) (ref :: REF | eff) a -> String -> a -> Eff (ref :: REF | eff) Unit
putIxQueue q k x = putManyIxQueue q k (NonEmpty x [])


-- | Application policy is such that the inputs are stored in the named handler's "pending" values, if a handler isn't registered.
--   If so, apply the handler uniformly across the values, according to `t`'s `Traversable` instance.
putManyIxQueue :: forall eff a t rw. Traversable t => IxQueue (write :: WRITE | rw) (ref :: REF | eff) a -> String -> NonEmpty t a -> Eff (ref :: REF | eff) Unit
putManyIxQueue (IxQueue {individual}) k xss = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing ->
      -- store locally pending values
      writeRef individual (StrMap.insert k (Left xsAsArray) hs)
    Just ePH -> case ePH of
      -- append locally pending values
      Left pending -> writeRef individual (StrMap.insert k (Left (appendNonEmpty pending xsAsArray)) hs)
      -- suit handlers
      Right h -> traverse_ h xss
  where
    xsAsArray :: NonEmpty Array a
    xsAsArray = case xss of
      NonEmpty x xs -> NonEmpty x (foldr Array.cons [] xs)



broadcastIxQueue :: forall eff a rw. IxQueue (write :: WRITE | rw) (ref :: REF | eff) a -> a -> Eff (ref :: REF | eff) Unit
broadcastIxQueue q x = broadcastManyIxQueue q (NonEmpty x [])


broadcastManyIxQueue :: forall eff a t rw. Traversable t => IxQueue (write :: WRITE | rw) (ref :: REF | eff) a -> NonEmpty t a -> Eff (ref :: REF | eff) Unit
broadcastManyIxQueue q xs = broadcastManyExceptIxQueue q [] xs


broadcastExceptIxQueue :: forall eff a rw. IxQueue (write :: WRITE | rw) (ref :: REF | eff) a -> Array String -> a -> Eff (ref :: REF | eff) Unit
broadcastExceptIxQueue q ex x = broadcastManyExceptIxQueue q ex (NonEmpty x [])


-- | Application policy is such that the inputs will be applied uniformly to all handlers, sorted by their keyed ordering, per input - directed by `t`'s `Traversable` instance.
--   Values are stored globally iff. there are no handlers, and locally if there's already pending values.
broadcastManyExceptIxQueue :: forall eff a t rw. Traversable t => IxQueue (write :: WRITE | rw) (ref :: REF | eff) a -> Array String -> NonEmpty t a -> Eff (ref :: REF | eff) Unit
broadcastManyExceptIxQueue (IxQueue {individual,broadcast}) excluding xss = do
  hs <- readRef individual

  let hasHandler (Right _) = true
      hasHandler _ = false

  if StrMap.isEmpty (StrMap.filter hasHandler hs)
    then modifyRef broadcast (\pending -> pending <> xsAsArray')
    else
      let go x = do
            hs' <- readRef individual
            let go' k ePH
                  | k `Array.notElem` excluding = case ePH of
                      Left pending -> writeRef individual (StrMap.insert k (Left (appendNonEmpty pending (NonEmpty x []))) hs')
                      Right h -> h x
                  | otherwise = pure unit
            void (traverseWithIndex go' hs')
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
onIxQueue :: forall eff a rw. IxQueue (read :: READ | rw) (ref :: REF | eff) a -> String -> (Handler (ref :: REF | eff) a) -> Eff (ref :: REF | eff) Unit
onIxQueue (IxQueue {individual,broadcast}) k f = do
  bs <- readRef broadcast
  -- consume pending global values
  unless (Array.null bs) $ do
    writeRef broadcast []
    traverse_ f bs
  hs <- readRef individual
  -- consume pending local values
  case StrMap.lookup k hs of
    Nothing -> pure unit
    Just ePH -> case ePH of
      Left pending -> traverse_ f pending
      Right _ -> pure unit
  writeRef individual (StrMap.insert k (Right f) hs)


onceIxQueue :: forall eff a rw. IxQueue (read :: READ | rw) (ref :: REF | eff) a -> String -> (Handler (ref :: REF | eff) a) -> Eff (ref :: REF | eff) Unit
onceIxQueue q@(IxQueue {broadcast,individual}) k f = do
  bs <- readRef broadcast
  case Array.uncons bs of
    Just {head,tail} -> do
      writeRef broadcast tail
      f head
    Nothing -> do
      hs <- readRef individual
      case StrMap.lookup k hs of
        Just (Left (NonEmpty x xs)) -> do
          case Array.uncons xs of
            Nothing ->
              writeRef individual (StrMap.delete k hs)
            Just {head,tail} ->
              writeRef individual (StrMap.insert k (Left (NonEmpty head tail)) hs)
          f x
        _ ->
          let f' x = do
                writeRef individual (StrMap.delete k hs)
                f x
          in  writeRef individual (StrMap.insert k (Right f') hs)


drawIxQueue :: forall rw eff a. IxQueue (read :: READ | rw) (ref :: REF | eff) a -> String -> Aff (ref :: REF | eff) a
drawIxQueue q k = makeAff \resolve -> do
  onceIxQueue q k (resolve <<< Right)
  pure nonCanceler


readIxQueue :: forall eff a rw. IxQueue rw (ref :: REF | eff) a -> String -> Eff (ref :: REF | eff) (Array a)
readIxQueue (IxQueue {individual}) k = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> pure []
    Just ePH -> case ePH of
      Left (NonEmpty x xs) -> pure (Array.cons x xs)
      Right _ -> pure []


readBroadcastIxQueue :: forall eff a rw. IxQueue rw (ref :: REF | eff) a -> Eff (ref :: REF | eff) (Array a)
readBroadcastIxQueue (IxQueue {broadcast}) = readRef broadcast


-- | Removes locally pending inputs for a specific key
takeIxQueue :: forall eff a rw. IxQueue (write :: WRITE | rw) (ref :: REF | eff) a -> String -> Eff (ref :: REF | eff) (Array a)
takeIxQueue (IxQueue {individual}) k = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> pure []
    Just ePH -> case ePH of
      Left (NonEmpty x xs) -> do
        writeRef individual (StrMap.delete k hs)
        pure (Array.cons x xs)
      Right _ -> pure []


-- | Removes only the globally pending inputs
takeBroadcastIxQueue :: forall eff a rw. IxQueue (write :: WRITE | rw) (ref :: REF | eff) a -> Eff (ref :: REF | eff) (Array a)
takeBroadcastIxQueue (IxQueue {broadcast}) = do
  xs <- readRef broadcast
  writeRef broadcast []
  pure xs


-- | Unregisters a handler, returns whether one existed
delIxQueue :: forall eff a rw. IxQueue (read :: READ | rw) (ref :: REF | eff) a -> String -> Eff (ref :: REF | eff) Boolean
delIxQueue (IxQueue {individual}) k = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> pure false
    Just ePH -> case ePH of
      Left pending -> pure false
      Right _ -> do
        writeRef individual (StrMap.delete k hs)
        pure true


-- | Removes all handlers, but preserves pending data
clearIxQueue :: forall eff a rw. IxQueue (read :: READ | rw) (ref :: REF | eff) a -> Eff (ref :: REF | eff) Unit
clearIxQueue q@(IxQueue{individual}) = do
  hs <- readRef individual
  traverse_ (\k -> unit <$ delIxQueue q k) (StrMap.keys hs)


-- | Applies a nullary named handler, to remove any globally pending data
drainIxQueue :: forall eff a rw. IxQueue (read :: READ | rw) (ref :: REF | eff) a -> String -> Eff (ref :: REF | eff) Unit
drainIxQueue q k = onIxQueue q k \_ -> pure unit




appendNonEmpty :: forall a. NonEmpty Array a -> NonEmpty Array a -> NonEmpty Array a
appendNonEmpty (NonEmpty x xs) (NonEmpty y ys) = NonEmpty x (xs <> [y] <> ys)
