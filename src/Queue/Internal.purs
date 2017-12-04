module Queue.Internal where

import Prelude
import Data.Either (Either (..))
import Data.Traversable (traverse_)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef)


type Handler eff a = a -> Eff eff Unit

newtype Queue eff a = Queue (Ref (Either (Array a) (Array (Handler eff a))))


newQueue :: forall eff a. Eff (ref :: REF | eff) (Queue (ref :: REF | eff) a)
newQueue = Queue <$> newRef (Left [])


putQueue :: forall eff a. Queue (ref :: REF | eff) a -> a -> Eff (ref :: REF | eff) Unit
putQueue q x = putManyQueue q [x]


putManyQueue :: forall eff a. Queue (ref :: REF | eff) a -> Array a -> Eff (ref :: REF | eff) Unit
putManyQueue (Queue queue) xs = do
  ePH <- readRef queue
  case ePH of
    Left pending -> writeRef queue (Left (pending <> xs))
    Right handlers -> traverse_ (\x -> traverse_ (\f -> f x) handlers) xs


onQueue :: forall eff a. Queue (ref :: REF | eff) a -> Handler (ref :: REF | eff) a -> Eff (ref :: REF | eff) Unit
onQueue (Queue queue) f = do
  ePH <- readRef queue
  case ePH of
    Left pending -> do
      traverse_ f pending
      writeRef queue (Right [f])
    Right handlers ->
      writeRef queue (Right (handlers <> [f]))


-- onceQueue :: forall eff a. Queue (ref :: REF | eff) a -> Handler (ref :: REF | eff) a -> Eff (ref :: REF | eff) Unit
-- onceQueue (Queue queue) f' = do
--   hasRun <- newRef false
--   let f x = do
--         r <- readRef hasRun
--         if r
--           then pure unit
--           else do
--             f' x
--             writeRef hasRun true
--   ePH <- readRef queue
--   case ePH of
--     Left pending -> do
--       case Array.uncons pending of
--         Nothing -> pure unit
--         Just {head,tail} -> do
--           f head
--           writeRef hasRun true
--           if Array.null tail
--             then writeRef queue (Right [f])
--             else writeRef queue (Left tail)
--     Right handlers ->
--       writeRef queue (Right (handlers <> [f]))


readQueue :: forall eff a. Queue (ref :: REF | eff) a -> Eff (ref :: REF | eff) (Array a)
readQueue (Queue queue) = do
  ePH <- readRef queue
  case ePH of
    Left pending -> pure pending
    Right _ -> pure []


takeQueue :: forall eff a. Queue (ref :: REF | eff) a -> Eff (ref :: REF | eff) (Array a)
takeQueue (Queue queue) = do
  ePH <- readRef queue
  case ePH of
    Left pending -> do
      writeRef queue (Left [])
      pure pending
    Right _ -> pure []
