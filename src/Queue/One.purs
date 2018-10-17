module Queue.One
  ( module Queue.Types
  , Queue (..), new
  , put, putMany, on, once, draw, take, read, del, drain
  ) where

import Queue.Types (kind SCOPE, READ, WRITE, class QueueScope, Handler)

import Prelude
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Traversable (class Traversable, traverse_, for_)
import Data.Array as Array
import Data.NonEmpty (NonEmpty (..))
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Ref (Ref)
import Effect.Ref as Ref




newtype Queue (rw :: # SCOPE) a =
  Queue (Ref (Either (Array a) (Handler a)))


new :: forall a. Effect (Queue (read :: READ, write :: WRITE) a)
new = Queue <$> Ref.new (Left [])


instance queueScopeQueueOne :: QueueScope Queue where
  readOnly     (Queue q) = Queue q
  allowWriting (Queue q) = Queue q
  writeOnly    (Queue q) = Queue q
  allowReading (Queue q) = Queue q


put :: forall rw a. Queue (write :: WRITE | rw) a -> a -> Effect Unit
put q x = putMany q (NonEmpty x [])


putMany:: forall rw a t
        . Traversable t
       => Queue (write :: WRITE | rw) a
       -> NonEmpty t a
       -> Effect Unit
putMany(Queue queue) xss = do
  for_ xss \x -> do
    ePH <- Ref.read queue
    case ePH of
      Left pending -> Ref.write (Left (pending <> [x])) queue
      Right f -> f x


on :: forall rw a. Queue (read :: READ | rw) a -> Handler a -> Effect Unit
on (Queue queue) f = do
  ePH <- Ref.read queue
  case ePH of
    Left pending -> do
      traverse_ f pending
      Ref.write (Right f) queue
    Right _ ->
      Ref.write (Right f) queue


-- | Treat this as the only handler, and on the next input, clear all handlers.
once :: forall rw a. Queue (read :: READ | rw) a -> Handler a -> Effect Unit
once q@(Queue queue) f' = do
  let f x = do
        del q
        f' x
  ePH <- Ref.read queue
  case ePH of
    Left pending -> do
      case Array.uncons pending of
        Nothing ->
          Ref.write (Right f) queue
        Just {head,tail} -> do
          f' head
          Ref.write (Left tail) queue
    Right _ ->
      Ref.write (Right f) queue


draw :: forall rw a. Queue (read :: READ | rw) a -> Aff a
draw q = makeAff \resolve -> do
  once q (resolve <<< Right)
  pure nonCanceler


read :: forall rw a. Queue rw a -> Effect (Array a)
read (Queue queue) = do
  ePH <- Ref.read queue
  case ePH of
    Left pending -> pure pending
    Right _ -> pure []


take :: forall rw a. Queue (write :: WRITE | rw) a -> Effect (Array a)
take (Queue queue) = do
  ePH <- Ref.read queue
  case ePH of
    Left pending -> do
      Ref.write (Left []) queue
      pure pending
    Right _ -> pure []


-- | Removes the registered callbacks, if any.
del :: forall rw a. Queue (read :: READ | rw) a -> Effect Unit
del (Queue queue) = do
  ePH <- Ref.read queue
  case ePH of
    Left _ -> pure unit
    Right _ -> Ref.write (Left []) queue



drain :: forall rw a. Queue (read :: READ | rw) a -> Effect Unit
drain q = on q \_ -> pure unit
