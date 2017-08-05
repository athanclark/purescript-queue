module IxQueue
  ( IxQueue, newIxQueue, putIxQueue, injectIxQueue, onIxQueue, delIxQueue
  ) where

import Prelude
import Queue (Queue, newQueue, putQueue, onQueue)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe (..))
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef, modifyRef)
import Signal.Channel (CHANNEL)


newtype IxQueue k a = IxQueue (Ref (Map k (Queue a)))


newIxQueue :: forall eff k a
            . Eff ( channel :: CHANNEL
                  , ref     :: REF
                  | eff) (IxQueue k a)
newIxQueue = IxQueue <$> newRef Map.empty


putIxQueue :: forall eff k a
            . Ord k
           => IxQueue k a
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


injectIxQueue :: forall eff k a
               . Ord k
              => IxQueue k a
              -> k
              -> Queue a
              -> Eff ( ref     :: REF
                     | eff) Unit
injectIxQueue (IxQueue qsRef) k q =
  modifyRef qsRef (Map.insert k q)


onIxQueue :: forall eff k a
           . Ord k
          => IxQueue k a
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
           => IxQueue k a
           -> k
           -> Eff ( channel :: CHANNEL
                  , ref     :: REF
                  | eff) Unit
delIxQueue (IxQueue qsRef) k =
  modifyRef qsRef (Map.delete k)