module IxQueue
  ( module Queue.Scope
  , IxQueue (..)
  , readOnly, writeOnly, allowReading, allowWriting
  , newIxQueue, putIxQueue, putManyIxQueue
  , broadcastIxQueue, broadcastManyIxQueue
  , onIxQueue, onceIxQueue
  , readBroadcastIxQueue, readIxQueue, takeBroadcastIxQueue, takeIxQueue
  , delIxQueue, clearIxQueue
  ) where

import Queue.Scope (kind SCOPE, READ, WRITE)

import Prelude
import Data.StrMap (StrMap)
import Data.StrMap as StrMap
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Tuple (Tuple (..))
import Data.Traversable (traverse_)
import Data.Array as Array
import Control.Monad.Eff (Eff, kind Effect)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef, modifyRef)


newtype IxQueue (rw :: # SCOPE) (eff :: # Effect) a = IxQueue
  { individual :: Ref (StrMap (Either (Array a) (a -> Eff eff Unit)))
  , broadcast  :: Ref (Array a)
  }


readOnly :: forall rw eff a. IxQueue (read :: READ | rw) eff a -> IxQueue (read :: READ) eff a
readOnly (IxQueue xs) = IxQueue xs

allowWriting :: forall rw eff a. IxQueue (read :: READ) eff a -> IxQueue (read :: READ | rw) eff a
allowWriting (IxQueue xs) = IxQueue xs

writeOnly :: forall rw eff a. IxQueue (write :: WRITE | rw) eff a -> IxQueue (write :: WRITE) eff a
writeOnly (IxQueue xs) = IxQueue xs

allowReading :: forall rw eff a. IxQueue (write :: WRITE) eff a -> IxQueue (write :: WRITE | rw) eff a
allowReading (IxQueue xs) = IxQueue xs


newIxQueue :: forall eff a. Eff (ref :: REF | eff) (IxQueue (read :: READ, write :: WRITE) (ref :: REF | eff) a)
newIxQueue = do
  individual <- newRef StrMap.empty
  broadcast <- newRef []
  pure (IxQueue {individual,broadcast})

putIxQueue :: forall eff a rw. IxQueue (write :: WRITE | rw) (ref :: REF | eff) a -> String -> a -> Eff (ref :: REF | eff) Unit
putIxQueue q k x = putManyIxQueue q k [x]

putManyIxQueue :: forall eff a rw. IxQueue (write :: WRITE | rw) (ref :: REF | eff) a -> String -> Array a -> Eff (ref :: REF | eff) Unit
putManyIxQueue (IxQueue {individual}) k xs = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> do
      writeRef individual (StrMap.insert k (Left xs) hs)
    Just ePH -> case ePH of
      Left pending -> writeRef individual (StrMap.insert k (Left (pending <> xs)) hs)
      Right h -> traverse_ h xs



broadcastIxQueue :: forall eff a rw. IxQueue (write :: WRITE | rw) (ref :: REF | eff) a -> a -> Eff (ref :: REF | eff) Unit
broadcastIxQueue q x = broadcastManyIxQueue q [x]


broadcastManyIxQueue :: forall eff a rw. IxQueue (write :: WRITE | rw) (ref :: REF | eff) a -> Array a -> Eff (ref :: REF | eff) Unit
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


onIxQueue :: forall eff a rw. IxQueue (read :: READ | rw) (ref :: REF | eff) a -> String -> (a -> Eff (ref :: REF | eff) Unit) -> Eff (ref :: REF | eff) Unit
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


onceIxQueue :: forall eff a rw. IxQueue (read :: READ | rw) (ref :: REF | eff) a -> String -> (a -> Eff (ref :: REF | eff) Unit) -> Eff (ref :: REF | eff) Unit
onceIxQueue q k f = do
  (hasRun :: Ref Boolean) <- newRef false
  onIxQueue q k \x -> do
    r <- readRef hasRun
    unless r $ do
      f x
      writeRef hasRun true
      unit <$ delIxQueue q k


readIxQueue :: forall eff a rw. IxQueue rw (ref :: REF | eff) a -> String -> Eff (ref :: REF | eff) (Array a)
readIxQueue (IxQueue {individual}) k = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> pure []
    Just ePH -> case ePH of
      Left pending -> pure pending
      Right _ -> pure []


readBroadcastIxQueue :: forall eff a rw. IxQueue rw (ref :: REF | eff) a -> Eff (ref :: REF | eff) (Array a)
readBroadcastIxQueue (IxQueue {broadcast}) = readRef broadcast


takeIxQueue :: forall eff a rw. IxQueue (write :: WRITE | rw) (ref :: REF | eff) a -> String -> Eff (ref :: REF | eff) (Array a)
takeIxQueue (IxQueue {individual}) k = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> pure []
    Just ePH -> case ePH of
      Left pending -> do
        writeRef individual (StrMap.insert k (Left []) hs)
        pure pending
      Right _ -> pure []


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
        writeRef individual (StrMap.insert k (Left []) hs)
        pure true


clearIxQueue :: forall eff a rw. IxQueue (read :: READ | rw) (ref :: REF | eff) a -> Eff (ref :: REF | eff) Unit
clearIxQueue q@(IxQueue{individual}) = do
  hs <- readRef individual
  traverse_ (\k -> unit <$ delIxQueue q k) (StrMap.keys hs)
