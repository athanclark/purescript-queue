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
import Foreign.Object (empty, filter, freezeST, isEmpty, thawST, keys, lookup, insert) as Object
import Foreign.Object.ST (poke, peek, delete) as Object
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Tuple (Tuple (..))
import Data.Traversable (for_)
import Data.FoldableWithIndex (traverseWithIndex_)
import Data.Traversable (traverse_)
import Data.Array (head, null, notElem) as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty (singleton, toArray, fromArray, uncons) as ArrayNE
import Data.Array.ST (push, pushAll, splice, thaw, unsafeFreeze, withArray) as Array
import Control.Monad.ST (ST)
import Control.Monad.ST (run) as ST
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Partial.Unsafe (unsafePartial)

type Individual a = Object (Either (NonEmptyArray a) (Handler a))

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

-- | Supply a single input to the indexed queue.
put :: forall a rw. IxQueue (write :: WRITE | rw) a -> String -> a -> Effect Unit
put q k x = putMany q k (ArrayNE.singleton x)


-- | Application policy is such that the inputs are stored in the named handler's "pending" values,
--   if a handler isn't registered. If so, apply the handler uniformly across the values.
putMany :: forall a rw
         . IxQueue (write :: WRITE | rw) a
        -> String
        -> NonEmptyArray a
        -> Effect Unit
putMany (IxQueue {individual}) k xss =
  for_ xss \x -> do
    hs <- Ref.read individual
    case Object.lookup k hs of
      Nothing ->
        -- store locally pending values
        let obj = ST.run go
            go :: forall r. ST r (Individual a)
            go = do
              o <- Object.thawST hs
              o' <- Object.poke k (Left (ArrayNE.singleton x)) o
              Object.freezeST o'
        in  Ref.write obj individual
      Just ePH -> case ePH of
        -- append locally pending values
        Left pending ->
          let obj = ST.run go
              go :: forall r. ST r (Individual a)
              go = do
                pending' <- Array.withArray (Array.push x) (ArrayNE.toArray pending)
                o <- Object.thawST hs
                o' <- Object.poke k (Left (unsafeFromArray pending')) o
                Object.freezeST o'
          in  Ref.write obj individual
        -- suit handlers
        Right h -> h x



broadcast :: forall a rw. IxQueue (write :: WRITE | rw) a -> a -> Effect Unit
broadcast q x = broadcastMany q (ArrayNE.singleton x)


broadcastMany :: forall a rw. IxQueue (write :: WRITE | rw) a -> NonEmptyArray a -> Effect Unit
broadcastMany q xs = broadcastManyExcept q [] xs


broadcastExcept :: forall a rw. IxQueue (write :: WRITE | rw) a -> Array String -> a -> Effect Unit
broadcastExcept q ex x = broadcastManyExcept q ex (ArrayNE.singleton x)


-- | Application policy is such that the inputs will be applied uniformly to all handlers, sorted by
--   their keyed ordering, per input. Values are stored globally iff. there are no handlers, and locally
--   if there's already pending values.
broadcastManyExcept :: forall a rw
                     . IxQueue (write :: WRITE | rw) a
                    -> Array String -- ^ "Excluding"
                    -> NonEmptyArray a
                    -> Effect Unit
broadcastManyExcept (IxQueue {individual,broadcast:broadcast'}) excluding xss = do
  hs <- Ref.read individual

  let hasHandler :: Either (NonEmptyArray a) (Handler a) -> Boolean
      hasHandler (Right _) = true
      hasHandler _ = false

  pendingB <- Ref.read broadcast'

  if Object.isEmpty (Object.filter hasHandler hs)
    then let pendingB' = ST.run (Array.withArray (Array.pushAll (ArrayNE.toArray xss)) pendingB)
         in  Ref.write pendingB' broadcast'
    else
      let go :: a -> Effect Unit
          go x = do
            hs' <- Ref.read individual
            let go' :: String -> Either (NonEmptyArray a) (Handler a) -> Effect Unit
                go' k ePH =
                  when (k `Array.notElem` excluding) $ case ePH of
                    Left pending ->
                      let obj = ST.run go1
                          go1 :: forall r. ST r (Individual a)
                          go1 = do
                            pending' <- Array.withArray (Array.push x) (ArrayNE.toArray pending)
                            hs'' <- Object.thawST hs'
                            _ <- Object.poke k (Left (unsafeFromArray pending')) hs''
                            Object.freezeST hs''
                      in  Ref.write obj individual
                    Right h -> h x
            traverseWithIndex_ go' hs'
      in  traverse_ go xss


-- | Application policy is such that the globally pending inputs will be extracted and applied
--   to the handler, if they exist, and likewise to the locally pending inputs,
--   before registering the handler under the name.
on :: forall a rw. IxQueue (read :: READ | rw) a -> String -> Handler a -> Effect Unit
on (IxQueue {individual,broadcast:b}) k f = do
  bs <- Ref.read b
  -- consume pending global values
  unless (Array.null bs) $ do
    Ref.write [] b
    traverse_ f bs
  hs <- Ref.read individual
  Ref.write (Object.insert k (Right f) hs) individual
  case Object.lookup k hs of
    Nothing -> pure unit
    Just ePH -> case ePH of
      Left pending -> traverse_ f pending
      Right _ -> pure unit


once :: forall a rw. IxQueue (read :: READ | rw) a -> String -> Handler a -> Effect Unit
once q@(IxQueue {broadcast:b,individual}) k f = do
  bs <- Ref.read b
  hs <- Ref.read individual
  let go :: forall r. ST r (Effect Unit)
      go = do
        bs' <- Array.thaw bs
        h <- Array.splice 0 1 [] bs'
        case Array.head h of
          Just h' -> do
            bs'' <- Array.unsafeFreeze bs'
            pure do
              Ref.write bs'' b
              f h'
          Nothing -> do
            hs' <- Object.thawST hs
            mX <- Object.peek k hs'
            case mX of
              Just (Left xss) -> do
                let {head:x,tail:xs} = ArrayNE.uncons xss
                    action :: Effect Unit
                    action = case ArrayNE.fromArray xs of
                      Nothing ->
                        let obj = ST.run go1
                            go1 :: forall r1. ST r1 (Individual a)
                            go1 = do
                              hs'' <- Object.thawST hs
                              _ <- Object.delete k hs''
                              Object.freezeST hs''
                        in  Ref.write obj individual
                      Just xs' ->
                        let obj = ST.run go1
                            go1 :: forall r1. ST r1 (Individual a)
                            go1 = do
                              hs'' <- Object.thawST hs
                              _ <- Object.poke k (Left xs') hs''
                              Object.freezeST hs''
                        in  Ref.write obj individual
                pure do
                  action
                  f x
              _ -> do
                let f' x = do
                      let obj = ST.run go1
                          go1 :: forall r1. ST r1 (Individual a)
                          go1 = do
                            hs'' <- Object.thawST hs
                            _ <- Object.delete k hs''
                            Object.freezeST hs''
                      Ref.write obj individual
                      f x
                _ <- Object.poke k (Right f') hs'
                obj <- Object.freezeST hs'
                pure (Ref.write obj individual)
  ST.run go

  -- case Array.uncons bs of
  --   Just {head,tail} -> do
  --     Ref.write tail b
  --     f head
  --   Nothing -> do
  --     hs <- Ref.read individual
  --     case Object.lookup k hs of
  --       Just (Left (NonEmpty x xs)) -> do
  --         case Array.uncons xs of
  --           Nothing ->
  --             Ref.write (Object.delete k hs) individual
  --           Just {head,tail} ->
  --             Ref.write (Object.insert k (Left (NonEmpty head tail)) hs) individual
  --         f x
  --       _ ->
  --         let f' x = do
  --               Ref.write (Object.delete k hs) individual
  --               f x
  --         in  Ref.write (Object.insert k (Right f') hs) individual


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
      Left xss -> pure (ArrayNE.toArray xss)
      Right _ -> pure []


readBroadcast :: forall a rw. IxQueue rw a -> Effect (Array a)
readBroadcast (IxQueue {broadcast:b}) = Ref.read b


-- | Removes locally pending inputs for a specific key
take :: forall a rw. IxQueue (write :: WRITE | rw) a -> String -> Effect (Array a)
take (IxQueue {individual}) k = do
  hs <- Ref.read individual
  let mNew = ST.run go
      go :: forall r. ST r (Maybe (Tuple (Array a) (Individual a)))
      go = do
        o <- Object.thawST hs
        mX <- Object.peek k o
        case mX of
          Nothing -> pure Nothing
          Just ePH -> case ePH of
            Right _ -> pure Nothing
            Left xss -> do
              _ <- Object.delete k o
              Just <<< Tuple (ArrayNE.toArray xss) <$> Object.freezeST o
  case mNew of
    Nothing -> pure []
    Just (Tuple pending obj) -> do
      Ref.write obj individual
      pure pending


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
  let mNew = ST.run go
      go :: forall r. ST r (Maybe (Individual a))
      go = do
        o <- Object.thawST hs
        mX <- Object.peek k o
        case mX of
          Nothing -> pure Nothing
          Just ePH -> case ePH of
            Left _ -> pure Nothing
            Right _ -> do
              _ <- Object.delete k o
              Just <$> Object.freezeST o
  case mNew of
    Nothing -> pure false
    Just obj -> do
      Ref.write obj individual
      pure true


-- | Removes all handlers, but preserves pending data
clear :: forall a rw. IxQueue (read :: READ | rw) a -> Effect Unit
clear q@(IxQueue{individual}) = do
  hs <- Ref.read individual
  traverse_ (\k -> unit <$ del q k) (Object.keys hs)


-- | Applies a nullary named handler, to remove any globally pending data
drain :: forall a rw. IxQueue (read :: READ | rw) a -> String -> Effect Unit
drain q k = on q k \_ -> pure unit





unsafeFromArray :: forall x. Array x -> NonEmptyArray x
unsafeFromArray xs = unsafePartial $ case ArrayNE.fromArray xs of
  Just xs' -> xs'
