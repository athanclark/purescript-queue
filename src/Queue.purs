module Queue
  ( Queue, newQueue, putQueue, putManyQueue, onQueue, readQueue, takeQueue
  ) where

import Prelude
import Data.Maybe (Maybe (..))
import Data.Traversable (traverse_)
import Control.Monad.Eff (kind Effect, Eff)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, modifyRef, writeRef)
-- import Signal (runSignal, sampleOn, constant)
-- import Signal.Channel (CHANNEL, Channel, channel, send, subscribe)
import IxSignal.Internal (IxSignal, subscribe, set, setIx)


type Pending a = {individual :: StrMap (Array a), broadcast :: Array a}

type Listening eff a = IxSignal eff (Array a)

newtype Queue eff a = Queue (Ref (Either (Pending a) (Listening eff a)))

newQueue :: forall eff a. Eff _ (Queue _ a)
newQueue = Queue <$> newRef (Left {individual: StrMap.empty, broadcast: []})

-- | Signal the listener with a value - note that there can be any number of writers to the queue.
putQueue :: forall eff a
          . Queue _ a
         -> a
         -> Eff _ Unit
putQueue q x = putManyQueue q [x]

putSpecificQueue :: forall eff a
          . Queue _ a
         -> a
         -> String
         -> Eff _ Unit
putSpecificQueue q x k = putManySpecificQueue q [x] k

putManySpecificQueue :: forall eff a
              . Queue _ a
             -> Array a
             -> String
             -> Eff _ Unit
putManySpecificQueue (Queue signal) xs k = do
  ePS <- readRef signal
  case ePS of
    Left {individual,broadcast} -> writeRef signal $ Left {individual: StrMap.insert k xs individual, broadcast}
    Right sig -> setIx k sig xs

putManyQueue :: forall eff a
              . Queue _ a
             -> Array a
             -> Eff _ Unit
putManyQueue (Queue signal) xs = do
  ePS <- readRef signal
  case ePS of
    Left {individual,broadcast} -> writeRef signal $ Left {individual, broadcast: broadcast <> xs}
    Right sig -> set sig xs


-- | Registers a named handler for the queue
onQueueSpecific :: forall eff a
                 . Queue _ a
                -> String
                -> (a -> Eff _ Unit)
                -> Eff _ Unit
onQueueSpecific (Queue signal) k f = do
  ePS <- readRef signal
  sig <- case ePS of
    Left {individual,broadcast} -> do
      sig' <- make $ broadcast <> case StrMap.lookup k individual of
        Nothing -> []
        Just xs -> xs
      writeRef signal (Right sig')
      pure sig'
    Right sig' -> pure sig'
  let go xs = do
        traverse_ f xs
        removeQueueLeaving q k []
  subscribeIx k go sig


-- onQueue :: forall eff a
--          . Queue a
--         -> (a -> Eff ( ref     :: REF
--                      | eff) Unit)
--         -> Eff ( ref     :: REF
--                | eff) Unit
-- onQueue q f = do
--   k <- show <$> genUUID
--   onQueueSpecific q k f


-- -- | Registers a named handler for the queue
-- onQueueSpecific :: forall eff a
--                  . Queue a
--                 -> String
--                 -> (a -> Eff (ref :: REF | eff) Unit)
--                 -> Eff (ref :: REF | eff) Unit
-- onQueueSpecific (Queue signal) k f = do
--   ePS <- readRef signal
--   sig <- case ePS of
--     Left pending -> do
--       sig' <- make sig
--       writeRef signal (Right sig')
--       pure sig'
--     Right sig' -> pure sig'
--   let go xs = do
--   subscribeIx k go sig

-- -- | Registers a named handler for the queue to be executed n times
-- onQueueSpecificN :: forall eff a
--                   . Queue a
--                  -> String
--                  -> Int
--                  -> (a -> Eff (ref :: REF | eff) Unit)
--                  -> Eff (ref :: REF | eff) Unit
-- onQueueSpecificN q@(Queue signal) k n f = do
--   nRuns <- newRef 0
--   ePS <- readRef signal
--   sig <- case ePS of
--     Left pending -> do
--       sig' <- make sig
--       writeRef signal (Right sig')
--       pure sig'
--     Right sig' -> pure sig'
--   let go xs = do
--         n' <- readRef nRuns
--         if n' < n
--           then do
--             let xs' = Array.take (n - n') xs
--             writeRef nRuns (n' + Array.length xs')
--             traverse_ f xs'
--             when (n' + Array.length xs >= n) $
--               removeQueueLeaving q k (Array.drop (n' + Array.length xs') xs) -- delete k sig -- early delete
--           else
--             removeQueueLeaving q k xs -- delete k sig -- just in case it doesn't delete early
--   subscribeIx k go sig

-- -- | Is only executed once before being removed
-- onQueueSpecificOnceMany :: forall eff a
--                          . Queue a
--                         -> Array (Tuple String a -> Eff (ref :: REF | eff) Unit)
--                         -> Eff (ref :: REF | eff) Unit
-- onQueueSpecificOnceMany q@(Queue signal) k fs = do
--   ePS <- readRef signal
--   case ePS of
--     Left pending -> case Array.uncons pending of
--       Nothing -> do
--         sig@(IxSignal {subscribers}) <- make []
--         subscribeIx k (\xs -> case Array.uncons xs of
--                           Nothing -> pure unit
--                           Just {head,tail} -> do
--                             traverse_ (\f -> f head) fs
--                             removeQueueLeaving q k tail
--                       ) sig
--         writeRef signal (Right sig)
--       Just {head,tail} -> do
--         traverse_ (\f -> f head) fs
--         writeRef signal (Left tail)
--     Right sig ->
--       subscribeIx k (\xs -> case Array.uncons xs of
--                         Nothing -> pure unit
--                         Just {head,tail} -> do
--                             f head
--                             removeQueueLeaving q k tail
--                     ) sig


-- -- if it becomes empty, go to Nothing
-- removeQueueLeaving :: forall eff a
--                     . Queue a
--                   -> String
--                   -> Array a
--                   -> Eff _ Unit
-- removeQueueLeaving (Queue signal) k xs = do
--   ePS <- readRef signal
--   case ePS of
--     Left pending -> writeRef signal (Left (pending <> xs))
--     Right sig@(IxSignal {subscribers}) -> do
--       isNull <- (StrMap.null <<< StrMap.delete k) <$> readRef subscribers
--       if isNull
--         then writeRef signal (Left xs)
--         else -- everyone else got it
--             delete k sig

-- -- | Read the entities in the queue without triggering the onQueue callback.
-- readQueue :: forall eff a
--            . Queue a
--           -> Eff ( ref :: REF
--                  | eff) (Array a)
-- readQueue (Queue {pending}) =
--   readRef pending

-- -- | Take the entities out of the queue without triggering the onQueue callback.
-- takeQueue :: forall eff a
--            . Queue a
--           -> Eff ( ref :: REF
--                  | eff) (Array a)
-- takeQueue (Queue {pending}) = do
--   xs <- readRef pending
--   writeRef pending []
--   pure xs
