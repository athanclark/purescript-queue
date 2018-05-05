module IxQueue
  ( module Queue.Types
  , IxQueue (..)
  , newIxQueue, putIxQueue, putManyIxQueue
  , broadcastIxQueue, broadcastManyIxQueue
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
import Data.Tuple (Tuple (..))
import Data.Traversable (traverse_)
import Data.Array as Array
import Control.Monad.Aff (Aff, makeAff, nonCanceler)
import Control.Monad.Eff (Eff, kind Effect)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef, modifyRef)


newtype IxQueue a (rw :: # SCOPE) (eff :: # Effect) = IxQueue
  { individual :: Ref (StrMap (Either (Array a) (Handler eff a)))
  , broadcast  :: Ref (Array a)
  }


newIxQueue :: forall eff a. Eff (ref :: REF | eff) (IxQueue a (read :: READ, write :: WRITE) (ref :: REF | eff))
newIxQueue = do
  individual <- newRef StrMap.empty
  broadcast <- newRef []
  pure (IxQueue {individual,broadcast})


instance queueScopeIxQueue :: QueueScope (IxQueue a) where
  readOnly     (IxQueue xs) = IxQueue xs
  allowWriting (IxQueue xs) = IxQueue xs
  writeOnly    (IxQueue xs) = IxQueue xs
  allowReading (IxQueue xs) = IxQueue xs

putIxQueue :: forall eff a rw. IxQueue a (write :: WRITE | rw) (ref :: REF | eff) -> String -> a -> Eff (ref :: REF | eff) Unit
putIxQueue q k x = putManyIxQueue q k [x]

putManyIxQueue :: forall eff a rw. IxQueue a (write :: WRITE | rw) (ref :: REF | eff) -> String -> Array a -> Eff (ref :: REF | eff) Unit
putManyIxQueue (IxQueue {individual}) k xs = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> do
      writeRef individual (StrMap.insert k (Left xs) hs)
    Just ePH -> case ePH of
      Left pending -> writeRef individual (StrMap.insert k (Left (pending <> xs)) hs)
      Right h -> traverse_ h xs



broadcastIxQueue :: forall eff a rw. IxQueue a (write :: WRITE | rw) (ref :: REF | eff) -> a -> Eff (ref :: REF | eff) Unit
broadcastIxQueue q x = broadcastManyIxQueue q [x]


broadcastManyIxQueue :: forall eff a rw. IxQueue a (write :: WRITE | rw) (ref :: REF | eff) -> Array a -> Eff (ref :: REF | eff) Unit
broadcastManyIxQueue (IxQueue {individual,broadcast}) xs = do
  hs <- readRef individual
  if StrMap.isEmpty $ StrMap.filter (\e -> case e of
                                        Right _ -> true
                                        _ -> false) hs
    then modifyRef broadcast (\pending -> pending <> xs)
    else do
      traverse_
        (\x ->
          traverse_
            (\(Tuple k ePH) ->
              case ePH of
                Left pending -> writeRef individual (StrMap.insert k (Left (pending <> [x])) hs)
                Right h -> h x
            )
            (StrMap.toUnfoldable hs :: Array (Tuple String (Either (Array a) (a -> Eff (ref :: REF | eff) Unit)))))
        xs


onIxQueue :: forall eff a rw. IxQueue a (read :: READ | rw) (ref :: REF | eff) -> String -> (Handler (ref :: REF | eff) a) -> Eff (ref :: REF | eff) Unit
onIxQueue (IxQueue {individual,broadcast}) k f = do
  bs <- readRef broadcast
  when (Array.null bs) $ do
    writeRef broadcast []
    traverse_ f bs
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> pure unit
    Just ePH -> case ePH of
      Left pending -> traverse_ f pending
      Right _ -> pure unit
  writeRef individual (StrMap.insert k (Right f) hs)


onceIxQueue :: forall eff a rw. IxQueue a (read :: READ | rw) (ref :: REF | eff) -> String -> (Handler (ref :: REF | eff) a) -> Eff (ref :: REF | eff) Unit
onceIxQueue q k f = do
  (hasRun :: Ref Boolean) <- newRef false
  onIxQueue q k \x -> do
    r <- readRef hasRun
    unless r $ do
      f x
      writeRef hasRun true
      unit <$ delIxQueue q k


drawIxQueue :: forall rw eff a. IxQueue a (read :: READ | rw) (ref :: REF | eff) -> String -> Aff (ref :: REF | eff) a
drawIxQueue q k = makeAff \resolve -> do
  onceIxQueue q k (resolve <<< Right)
  pure nonCanceler


readIxQueue :: forall eff a rw. IxQueue a rw (ref :: REF | eff) -> String -> Eff (ref :: REF | eff) (Array a)
readIxQueue (IxQueue {individual}) k = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> pure []
    Just ePH -> case ePH of
      Left pending -> pure pending
      Right _ -> pure []


readBroadcastIxQueue :: forall eff a rw. IxQueue a rw (ref :: REF | eff) -> Eff (ref :: REF | eff) (Array a)
readBroadcastIxQueue (IxQueue {broadcast}) = readRef broadcast


takeIxQueue :: forall eff a rw. IxQueue a (write :: WRITE | rw) (ref :: REF | eff) -> String -> Eff (ref :: REF | eff) (Array a)
takeIxQueue (IxQueue {individual}) k = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> pure []
    Just ePH -> case ePH of
      Left pending -> do
        writeRef individual (StrMap.insert k (Left []) hs)
        pure pending
      Right _ -> pure []


takeBroadcastIxQueue :: forall eff a rw. IxQueue a (write :: WRITE | rw) (ref :: REF | eff) -> Eff (ref :: REF | eff) (Array a)
takeBroadcastIxQueue (IxQueue {broadcast}) = do
  xs <- readRef broadcast
  writeRef broadcast []
  pure xs


-- | Unregisters a handler, returns whether one existed
delIxQueue :: forall eff a rw. IxQueue a (read :: READ | rw) (ref :: REF | eff) -> String -> Eff (ref :: REF | eff) Boolean
delIxQueue (IxQueue {individual}) k = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> pure false
    Just ePH -> case ePH of
      Left pending -> pure false
      Right _ -> do
        writeRef individual (StrMap.insert k (Left []) hs)
        pure true


clearIxQueue :: forall eff a rw. IxQueue a (read :: READ | rw) (ref :: REF | eff) -> Eff (ref :: REF | eff) Unit
clearIxQueue q@(IxQueue{individual}) = do
  hs <- readRef individual
  traverse_ (\k -> unit <$ delIxQueue q k) (StrMap.keys hs)


drainIxQueue :: forall eff a rw. IxQueue a (read :: READ | rw) (ref :: REF | eff) -> String -> Eff (ref :: REF | eff) Unit
drainIxQueue q k = onIxQueue q k \_ -> pure unit
