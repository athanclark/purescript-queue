module IxQueue.Internal where

import Prelude
import Data.StrMap (StrMap)
import Data.StrMap as StrMap
import Data.Either (Either (..))
import Data.Maybe (Maybe (..))
import Data.Tuple (Tuple (..))
import Data.Traversable (traverse_)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Ref (REF, Ref, newRef, readRef, writeRef)


newtype IxQueue eff a = IxQueue
  { individual :: Ref (StrMap (Either (Array a) (a -> Eff eff Unit)))
  , default    :: Ref (Either (Array a) (Maybe String -> a -> Eff eff Unit))
  }


newIxQueue :: forall eff a. Eff (ref :: REF | eff) (IxQueue (ref :: REF | eff) a)
newIxQueue = do
  individual <- newRef StrMap.empty
  default <- newRef (Left [])
  pure (IxQueue {individual,default})

putIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> String -> a -> Eff (ref :: REF | eff) Unit
putIxQueue q k x = putManyIxQueue q k [x]

putManyIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> String -> Array a -> Eff (ref :: REF | eff) Unit
putManyIxQueue (IxQueue {individual,default}) k xs = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> do
      ePH <- readRef default
      case ePH of
        Left pending -> writeRef default (Left (pending <> xs))
        Right h -> traverse_ (h (Just k)) xs
    Just ePH -> case ePH of
      Left pending -> writeRef individual (StrMap.insert k (Left (pending <> xs)) hs)
      Right h -> traverse_ h xs

putOnlyIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> String -> a -> Eff (ref :: REF | eff) Unit
putOnlyIxQueue q k x = putOnlyManyIxQueue q k [x]

putOnlyManyIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> String -> Array a -> Eff (ref :: REF | eff) Unit
putOnlyManyIxQueue (IxQueue {individual}) k xs = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> writeRef individual (StrMap.insert k (Left xs) hs)
    Just ePH -> case ePH of
      Left pending -> writeRef individual (StrMap.insert k (Left (pending <> xs)) hs)
      Right h -> traverse_ h xs


broadcastIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> a -> Eff (ref :: REF | eff) Unit
broadcastIxQueue q x = broadcastManyIxQueue q [x]


broadcastManyIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> Array a -> Eff (ref :: REF | eff) Unit
broadcastManyIxQueue (IxQueue {individual,default}) xs = do
  ( do  ePH <- readRef default
        case ePH of
          Left pending -> writeRef default (Left (pending <> xs))
          Right h -> traverse_ (h Nothing) xs
    )
  hs <- readRef individual
  traverse_ (\x -> traverse_ (\(Tuple k ePH) -> case ePH of
                                 Left pending -> writeRef individual (StrMap.insert k (Left (pending <> [x])) hs)
                                 Right h -> h x
                             ) (StrMap.toUnfoldable hs :: Array (Tuple String (Either (Array a) (a -> Eff (ref :: REF | eff) Unit))))) xs


onDefaultIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> (Maybe String -> a -> Eff (ref :: REF | eff) Unit) -> Eff (ref :: REF | eff) Unit
onDefaultIxQueue (IxQueue {default}) f = do
  ePH <- readRef default
  case ePH of
    Left pending -> traverse_ (f Nothing) pending
    Right _ -> pure unit
  writeRef default (Right f)


onIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> String -> (a -> Eff (ref :: REF | eff) Unit) -> Eff (ref :: REF | eff) Unit
onIxQueue (IxQueue {individual}) k f = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> pure unit
    Just ePH -> case ePH of
      Left pending -> traverse_ f pending
      Right _ -> pure unit
  writeRef individual (StrMap.insert k (Right f) hs)


onceDefaultIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> (Maybe String -> a -> Eff (ref :: REF | eff) Unit) -> Eff (ref :: REF | eff) Unit
onceDefaultIxQueue q f = do
  (hasRun :: Ref Boolean) <- newRef false
  onDefaultIxQueue q \ms x -> do
    r <- readRef hasRun
    unless r $ do
      f ms x
      writeRef hasRun true
      unit <$ delDefaultIxQueue q


onceIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> String -> (a -> Eff (ref :: REF | eff) Unit) -> Eff (ref :: REF | eff) Unit
onceIxQueue q k f = do
  (hasRun :: Ref Boolean) <- newRef false
  onIxQueue q k \x -> do
    r <- readRef hasRun
    unless r $ do
      f x
      writeRef hasRun true
      unit <$ delIxQueue q k


readDefaultIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> Eff (ref :: REF | eff) (Array a)
readDefaultIxQueue (IxQueue {default}) = do
  ePH <- readRef default
  case ePH of
    Left pending -> pure pending
    Right _ -> pure []


readIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> String -> Eff (ref :: REF | eff) (Array a)
readIxQueue (IxQueue {individual}) k = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> pure []
    Just ePH -> case ePH of
      Left pending -> pure pending
      Right _ -> pure []


takeDefaultIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> Eff (ref :: REF | eff) (Array a)
takeDefaultIxQueue (IxQueue {default}) = do
  ePH <- readRef default
  case ePH of
    Left pending -> do
      writeRef default (Left [])
      pure pending
    Right _ -> pure []


takeIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> String -> Eff (ref :: REF | eff) (Array a)
takeIxQueue (IxQueue {individual}) k = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> pure []
    Just ePH -> case ePH of
      Left pending -> do
        writeRef individual (StrMap.insert k (Left []) hs)
        pure pending
      Right _ -> pure []


delDefaultIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> Eff (ref :: REF | eff) Boolean
delDefaultIxQueue (IxQueue {default}) = do
  ePH <- readRef default
  case ePH of
    Left pending -> pure false
    Right _ -> do
      writeRef default (Left [])
      pure true


-- | Unregisters a handler, returns whether one existed
delIxQueue :: forall eff a. IxQueue (ref :: REF | eff) a -> String -> Eff (ref :: REF | eff) Boolean
delIxQueue (IxQueue {individual}) k = do
  hs <- readRef individual
  case StrMap.lookup k hs of
    Nothing -> pure false
    Just ePH -> case ePH of
      Left pending -> pure false
      Right _ -> do
        writeRef individual (StrMap.insert k (Left []) hs)
        pure true
