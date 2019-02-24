-- | Queues with an indexed mapping of handlers - this is useful for sending messages to a set of recipients,
-- | either discriminately or via broadcast, where removing them individually from the queue is also necessary. This
-- | could be useful in interfaces where the set of listening handlers is unknown and dynamic, mimicking
-- | global access to updated values.

module IxQueue
  ( module Queue.Types
  , IxQueue (..)
  , new, put, putMany, pop, popMany
  , broadcast, broadcastMany
  , broadcastExcept, broadcastManyExcept
  , on, once, draw
  , readBroadcast, read
  , takeBroadcast, takeBroadcastMany, takeBroadcastAll
  , popBroadcast, popBroadcastMany
  , take, takeMany, takeAll
  , del, clear, drain, length, lengthBroadcast
  ) where

import Queue.Types (kind SCOPE, READ, WRITE, class QueueScope, Handler)

import Prelude (Unit, ($), (<$), bind, pure, unit, (<$>), discard, unless, when, (<<<), void, (<>))
import Foreign.Object (Object)
import Foreign.Object (empty, filter, freezeST, isEmpty, thawST, keys, lookup, insert) as Object
import Foreign.Object.ST (poke, peek, delete) as Object
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Tuple (Tuple (..))
import Data.Foldable (foldl)
import Data.Traversable (for_, traverse_, class Traversable)
import Data.FoldableWithIndex (traverseWithIndex_)
import Data.Array (head, null, notElem, snoc, drop, take, reverse, length) as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty (singleton, toArray, fromArray, uncons, snoc, length) as ArrayNE
import Data.Array.ST (splice, thaw, unsafeFreeze) as Array
import Control.Monad.ST (ST)
import Control.Monad.ST (run) as ST
import Effect (Effect)
import Effect.Aff (Aff, makeAff, effectCanceler)
import Effect.Ref (Ref)
import Effect.Ref as Ref

type Individual a = Object (Either (NonEmptyArray a) (Handler a))

newtype IxQueue (rw :: # SCOPE) a = IxQueue
  { individual :: Ref (Object (Either (NonEmptyArray a) (Handler a)))
                  -- either a nonempty set of pending vals, or a handler
  , broadcast  :: Ref (Array a) -- possibly empty set of pending values
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
put q k x = putMany q k [x]


-- | Application policy is such that the inputs are stored in the named handler's "pending" values,
--   if a handler isn't registered. If so, apply the handler uniformly across the values.
putMany :: forall a rw t
         . Traversable t
        => IxQueue (write :: WRITE | rw) a
        -> String
        -> t a
        -> Effect Unit
putMany (IxQueue {individual}) k xss =
  for_ xss \x -> do
    hs <- Ref.read individual
    case Object.lookup k hs of
      Nothing -> Ref.write (Object.insert k (Left (ArrayNE.singleton x)) hs) individual
      Just ePH -> case ePH of
        -- append locally pending values
        Left pending -> Ref.write (Object.insert k (Left (ArrayNE.snoc pending x)) hs) individual
        -- suit handlers
        Right h -> h x



broadcast :: forall a rw. IxQueue (write :: WRITE | rw) a -> a -> Effect Unit
broadcast q x = broadcastMany q [x]


broadcastMany :: forall a rw t. Traversable t => IxQueue (write :: WRITE | rw) a -> t a -> Effect Unit
broadcastMany q xs = broadcastManyExcept q [] xs


broadcastExcept :: forall a rw. IxQueue (write :: WRITE | rw) a -> Array String -> a -> Effect Unit
broadcastExcept q ex x = broadcastManyExcept q ex (ArrayNE.singleton x)


-- | Application policy is such that the inputs will be applied uniformly to all handlers, sorted by
--   their keyed ordering, per input. Values are stored globally iff. there are no handlers, and locally
--   if there's already pending values.
broadcastManyExcept :: forall a rw t
                     . Traversable t
                    => IxQueue (write :: WRITE | rw) a
                    -> Array String -- ^ "Excluding"
                    -> t a
                    -> Effect Unit
broadcastManyExcept (IxQueue {individual,broadcast:broadcast'}) excluding xss = do
  hs <- Ref.read individual

  let hasHandler :: Either (NonEmptyArray a) (Handler a) -> Boolean
      hasHandler (Right _) = true
      hasHandler _ = false

  pendingB <- Ref.read broadcast'

  if Object.isEmpty (Object.filter hasHandler hs)
    then  Ref.write (pendingB <> foldl Array.snoc [] xss) broadcast'
    else
      let go :: a -> Effect Unit
          go x = do
            hs' <- Ref.read individual
            let go' :: String -> Either (NonEmptyArray a) (Handler a) -> Effect Unit
                go' k ePH =
                  when (k `Array.notElem` excluding) $ case ePH of
                    Left pending ->
                      Ref.write (Object.insert k (Left (ArrayNE.snoc pending x)) hs') individual
                    Right h -> h x
            traverseWithIndex_ go' hs'
      in  traverse_ go xss


-- | Application policy is such that the globally pending inputs will be extracted and applied
--   to the handler, if they exist, and likewise to the locally pending inputs, after registering
--   the handler.
on :: forall a rw. IxQueue (read :: READ | rw) a -> String -> Handler a -> Effect Unit
on (IxQueue {individual,broadcast:b}) k f = do
  bs <- Ref.read b
  -- consume pending global values
  unless (Array.null bs) $ do
    Ref.write [] b
    traverse_ f bs
  hs <- Ref.read individual
  let go :: forall r. ST r (Tuple (Array a) (Individual a))
      go = do
        hs' <- Object.thawST hs
        mX <- Object.peek k hs'
        hs'' <- Object.poke k (Right f) hs'
        o <- Object.freezeST hs''
        case mX of
          Nothing -> pure (Tuple [] o) -- pure Nothing
          Just ePH -> do
            let p = case ePH of
                  Left pending -> ArrayNE.toArray pending
                  Right _ -> []
            pure (Tuple p o)
      mNew = ST.run go
  case mNew of
    Tuple pending obj -> do
      Ref.write obj individual
      traverse_ f pending


-- | Apply a handler to a specific index that deletes itself after being run, via broadcast or
--   targeted application.
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


-- | Pull the next asynchronous value out of a queue. Doesn't affect existing handlers (they will all receive the value as well). Canceling this action will remove the handler identified by the key.
draw :: forall rw a. IxQueue (read :: READ | rw) a -> String -> Aff a
draw q k = makeAff \resolve -> effectCanceler (void (del q k)) <$ once q k (resolve <<< Right)


-- | Read all pending values (if any) for a specific index, without removing them from the queue.
read :: forall a rw. IxQueue rw a -> String -> Effect (Array a)
read (IxQueue {individual}) k = do
  hs <- Ref.read individual
  case Object.lookup k hs of
    Nothing -> pure []
    Just ePH -> case ePH of
      Left xss -> pure (ArrayNE.toArray xss)
      Right _ -> pure []


-- | Read only broadcast pending values (if any), without removing them from the queue.
readBroadcast :: forall a rw. IxQueue rw a -> Effect (Array a)
readBroadcast (IxQueue {broadcast:b}) = Ref.read b


pop :: forall a rw. IxQueue (write :: WRITE | rw) a -> String -> Effect (Maybe a)
pop q k = Array.head <$> popMany q k 1


-- | Removes as many locally pending inputs for a specific key, in the order of youngest to oldest.
popMany :: forall a rw. IxQueue (write :: WRITE | rw) a -> String -> Int -> Effect (Array a)
popMany (IxQueue {individual}) k n = do
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
              let xss' = Array.reverse (ArrayNE.toArray xss)
                  rest = Array.reverse (Array.drop n xss')
                  unrest = Array.take n xss'
              void $ case ArrayNE.fromArray rest of
                Nothing -> Object.delete k o
                Just rest' -> Object.poke k (Left rest') o
              Just <<< Tuple unrest <$> Object.freezeST o
  case mNew of
    Nothing -> pure []
    Just (Tuple pending obj) -> do
      Ref.write obj individual
      pure pending


-- | Removes as many locally pending inputs for a specific key, in the order of oldest to youngest.
takeMany :: forall a rw. IxQueue (write :: WRITE | rw) a -> String -> Int -> Effect (Array a)
takeMany (IxQueue {individual}) k n = do
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
              let xss' = ArrayNE.toArray xss
                  rest = Array.drop n xss'
                  unrest = Array.take n xss'
              void $ case ArrayNE.fromArray rest of
                Nothing -> Object.delete k o
                Just rest' -> Object.poke k (Left rest') o
              Just <<< Tuple unrest <$> Object.freezeST o
  case mNew of
    Nothing -> pure []
    Just (Tuple pending obj) -> do
      Ref.write obj individual
      pure pending


-- | Removes locally pending inputs for a specific key
takeAll :: forall a rw. IxQueue (write :: WRITE | rw) a -> String -> Effect (Array a)
takeAll (IxQueue {individual}) k = do
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


take :: forall a rw. IxQueue (write :: WRITE | rw) a -> String -> Effect (Maybe a)
take q k = Array.head <$> takeMany q k 1


takeBroadcast :: forall a rw. IxQueue (write :: WRITE | rw) a -> Effect (Maybe a)
takeBroadcast q = Array.head <$> takeBroadcastMany q 1


-- | Removes only the globally pending inputs, oldest to youngest
takeBroadcastMany :: forall a rw. IxQueue (write :: WRITE | rw) a -> Int -> Effect (Array a)
takeBroadcastMany (IxQueue {broadcast:b}) n = do
  xs <- Ref.read b
  Ref.write (Array.drop n xs) b
  pure (Array.take n xs)


-- | Removes only the globally pending inputs
takeBroadcastAll :: forall a rw. IxQueue (write :: WRITE | rw) a -> Effect (Array a)
takeBroadcastAll (IxQueue {broadcast:b}) = do
  xs <- Ref.read b
  Ref.write [] b
  pure xs


popBroadcast :: forall a rw. IxQueue (write :: WRITE | rw) a -> Effect (Maybe a)
popBroadcast q = Array.head <$> popBroadcastMany q 1


-- | Removes only the globally pending inputs, oldest to youngest
popBroadcastMany :: forall a rw. IxQueue (write :: WRITE | rw) a -> Int -> Effect (Array a)
popBroadcastMany (IxQueue {broadcast:b}) n = do
  xs <- Array.reverse <$> Ref.read b
  Ref.write (Array.reverse (Array.drop n xs)) b
  pure ((Array.take n xs))


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


length :: forall a rw. IxQueue rw a -> String -> Effect Int
length (IxQueue{individual}) k = do
  hs <- Ref.read individual
  case Object.lookup k hs of
    Nothing -> pure 0
    Just ePH -> case ePH of
      Left pending -> pure (ArrayNE.length pending)
      Right _ -> pure 0


lengthBroadcast :: forall a rw. IxQueue rw a -> Effect Int
lengthBroadcast (IxQueue{broadcast:b}) = do
   Array.length <$> Ref.read b
