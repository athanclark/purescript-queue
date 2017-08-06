module IxQueue
  ( IxQueue, newIxQueue, putIxQueue, injectIxQueue, onIxQueue, delIxQueue
  ) where

import Prelude
import Queue (Queue, newQueue, putQueue, onQueue, takeQueue)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe (..))
import Data.Traversable (traverse_)
import Control.Monad.Eff (kind Effect, Eff)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef, modifyRef)
import Signal.Channel (CHANNEL)


newtype IxQueue (eff :: # Effect) k a = IxQueue (Ref (Map k (Queue eff a)))


newIxQueue :: forall eff k a
            . Eff ( channel :: CHANNEL
                  , ref     :: REF
                  | eff) (IxQueue (channel :: CHANNEL, ref :: REF | eff) k a)
newIxQueue = IxQueue <$> newRef Map.empty


putIxQueue :: forall eff k a
            . Ord k
           => IxQueue (channel :: CHANNEL, ref :: REF | eff) k a
           -> k
           -> a
           -> Eff ( channel :: CHANNEL
                  , ref     :: REF
                  | eff) Unit
putIxQueue (IxQueue qsRef) k x = do
  qs <- readRef qsRef
  case Map.lookup k qs of
    Nothing -> do
      q <- newQueue
      writeRef qsRef (Map.insert k q qs)
      putQueue q x
    Just q -> putQueue q x


-- | **Note**: if a Queue already exists in the IxQueue, then it _reads_
-- | all of the values in the existing queue before replacing it with the
-- | new one, then inserts the read entities.
injectIxQueue :: forall eff k a
               . Ord k
              => IxQueue (channel :: CHANNEL, ref :: REF | eff) k a
              -> k
              -> Queue (channel :: CHANNEL, ref :: REF | eff) a
              -> Eff ( channel :: CHANNEL
                     , ref     :: REF
                     | eff) Unit
injectIxQueue (IxQueue qsRef) k q = do
  qs <- readRef qsRef
  case Map.lookup k qs of
    Nothing ->
      writeRef qsRef (Map.insert k q qs)
    Just q' -> do
      xs <- takeQueue q'
      writeRef qsRef (Map.insert k q qs)
      traverse_ (putQueue q) xs


onIxQueue :: forall eff k a
           . Ord k
          => IxQueue (channel :: CHANNEL, ref :: REF | eff) k a
          -> k
          -> (a -> Eff ( channel :: CHANNEL
                       , ref     :: REF
                       | eff) Unit)
          -> Eff ( channel :: CHANNEL
                 , ref     :: REF
                 | eff) Unit
onIxQueue (IxQueue qsRef) k f = do
  qs <- readRef qsRef
  case Map.lookup k qs of
    Nothing -> do
      q <- newQueue
      writeRef qsRef (Map.insert k q qs)
      onQueue q f
    Just q -> onQueue q f


delIxQueue :: forall eff k a
            . Ord k
           => IxQueue (channel :: CHANNEL, ref :: REF | eff) k a
           -> k
           -> Eff ( channel :: CHANNEL
                  , ref     :: REF
                  | eff) Unit
delIxQueue (IxQueue qsRef) k =
  modifyRef qsRef (Map.delete k)
