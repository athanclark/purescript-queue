module Test.Main.IxQueue where

import Prelude
import IxQueue as IxQ
import Foreign.Object (Object)
import Foreign.Object as Object
import Data.Tuple (Tuple (..))
import Data.Maybe (Maybe (..))
import Data.Traversable (for, class Traversable, sequence_)
import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as ArrayNE
import Data.UUID (genUUID)
import Effect (Effect)
import Effect.Random (randomInt)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Effect.Timer (setTimeout)
import Effect.Console (log)
import Partial.Unsafe (unsafePartial)



putManyAfterOnSync :: forall a
                    . Eq a
                   => NonEmptyArray a
                   -> (Boolean -> Effect Unit)
                   -> Effect Unit
putManyAfterOnSync xs onComplete = do
  q <- IxQ.new
  k <- show <$> genUUID
  (obtained :: Ref (Array a)) <- Ref.new []
  IxQ.on q k \x -> do
    newXs <- Ref.modify (\ys -> ys `Array.snoc` x) obtained
    if Array.length newXs == ArrayNE.length xs
      then onComplete (newXs == ArrayNE.toArray xs)
      else pure unit
  IxQ.putMany q k xs


putManyBroadcastsAfterOnSync :: forall a
                              . Eq a
                             => NonEmptyArray a
                             -> (Boolean -> Effect Unit)
                             -> Effect Unit
putManyBroadcastsAfterOnSync xs onComplete = do
  q <- IxQ.new
  n <- randomInt 1 10
  let replicateM :: forall m. Monad m => Int -> (Int -> m Unit) -> m Unit
      replicateM n' x
        | n' == 1 = x n'
        | otherwise = do
          x n'
          replicateM (n' - 1) x
  (obtained :: Ref (Object (Array a))) <- do
    o <- Ref.new Object.empty
    replicateM n \_ -> do
      k <- show <$> genUUID
      void (Ref.modify (Object.insert k []) o)
    pure o
  obtainedObj <- Ref.read obtained
  let forObj :: forall a m. Applicative m => Object a -> (String -> a -> m Unit) -> m Unit
      forObj obj f = sequence_ (Object.toArrayWithKey f obj)
  forObj obtainedObj \k _ -> do
    IxQ.on q k $ \x -> do
      let go' zs = zs `Array.snoc` x
          go ys = Object.update (Just <<< go') k ys
      newXs <- Ref.modify go obtained
      if Object.all (\_ x -> Array.length x == ArrayNE.length xs) newXs
        then onComplete (Object.all (\_ z -> z == ArrayNE.toArray xs) newXs)
        else pure unit
  IxQ.broadcastMany q xs


putManyBeforeOnSync :: forall a
                    . Eq a
                   => NonEmptyArray a
                   -> (Boolean -> Effect Unit)
                   -> Effect Unit
putManyBeforeOnSync xs onComplete = do
  q <- IxQ.new
  k <- show <$> genUUID
  (obtained :: Ref (Array a)) <- Ref.new []
  IxQ.putMany q k xs
  IxQ.on q k \x -> do
    newXs <- Ref.modify (\ys -> ys `Array.snoc` x) obtained
    if Array.length newXs == ArrayNE.length xs
       then onComplete (newXs == ArrayNE.toArray xs)
       else pure unit


putManyAfterOnceAtLeastOnce :: forall a
                             . Eq a
                            => NonEmptyArray a
                            -> (Boolean -> Effect Unit)
                            -> Effect Unit
putManyAfterOnceAtLeastOnce xs onComplete = do
  q <- IxQ.new
  k <- show <$> genUUID
  IxQ.once q k \x -> onComplete (x == ArrayNE.head xs)
  IxQ.putMany q k xs


broadcastManyAfterOnceAtLeastOnce :: forall a
                                      . Eq a
                                     => NonEmptyArray a
                                     -> (Boolean -> Effect Unit)
                                     -> Effect Unit
broadcastManyAfterOnceAtLeastOnce xs onComplete = do
  q <- IxQ.new
  k <- show <$> genUUID
  IxQ.once q k \x -> onComplete (x == ArrayNE.head xs)
  IxQ.broadcastMany q xs


putManyAfterOnceOnlyOnce :: forall a
                          . Eq a
                         => NonEmptyArray a
                         -> (Boolean -> Effect Unit)
                         -> Effect Unit
putManyAfterOnceOnlyOnce xs onComplete = do
  q <- IxQ.new
  (valuesObtained :: Ref (Array a)) <- Ref.new []
  k <- show <$> genUUID
  IxQ.once q k \x -> void (Ref.modify (\ys -> ys `Array.snoc` x) valuesObtained)
  IxQ.putMany q k xs
  void $ setTimeout 100 do
    vs <- Ref.read valuesObtained
    onComplete (vs == [ArrayNE.head xs])


broadcastManyAfterOnceOnlyOnce :: forall a
                          . Eq a
                         => NonEmptyArray a
                         -> (Boolean -> Effect Unit)
                         -> Effect Unit
broadcastManyAfterOnceOnlyOnce xs onComplete = do
  q <- IxQ.new
  (valuesObtained :: Ref (Array a)) <- Ref.new []
  k <- show <$> genUUID
  IxQ.once q k \x -> void (Ref.modify (\ys -> ys `Array.snoc` x) valuesObtained)
  IxQ.broadcastMany q xs
  void $ setTimeout 100 do
    vs <- Ref.read valuesObtained
    onComplete (vs == [ArrayNE.head xs])


readIdempotent :: forall a
                . Eq a
               => NonEmptyArray a
               -> (Boolean -> Effect Unit)
               -> Effect Unit
readIdempotent xs onComplete = do
  q <- IxQ.new
  k <- show <$> genUUID
  IxQ.putMany q k xs
  r1 <- IxQ.read q k
  r2 <- IxQ.read q k
  onComplete (r1 == r2)


takeIdentity :: forall a
              . Eq a
             => NonEmptyArray a
             -> (Boolean -> Effect Unit)
             -> Effect Unit
takeIdentity xs onComplete = do
  q <- IxQ.new
  k <- show <$> genUUID
  IxQ.putMany q k xs
  ys <- IxQ.takeAll q k
  onComplete (ArrayNE.toArray xs == ys)


take2ndIdempotent :: forall a
                   . Eq a
                  => NonEmptyArray a
                  -> (Boolean -> Effect Unit)
                  -> Effect Unit
take2ndIdempotent xs onComplete = do
  q <- IxQ.new
  k <- show <$> genUUID
  IxQ.putMany q k xs
  _ <- IxQ.takeAll q k
  ys1 <- IxQ.takeAll q k
  ys2 <- IxQ.takeAll q k
  onComplete (ys1 == ys2 && ys2 == [])


delPendingIdentity :: forall a
                    . Eq a
                   => NonEmptyArray a
                   -> (Boolean -> Effect Unit)
                   -> Effect Unit
delPendingIdentity xs onComplete = do
  q <- IxQ.new
  k <- show <$> genUUID
  IxQ.drain q k
  _ <- IxQ.del q k
  IxQ.putMany q k xs
  ys <- IxQ.read q k
  onComplete (ArrayNE.toArray xs == ys)


drainConsumes :: forall a
               . Eq a
              => NonEmptyArray a
              -> (Boolean -> Effect Unit)
              -> Effect Unit
drainConsumes xs onComplete = do
  q <- IxQ.new
  k <- show <$> genUUID
  IxQ.drain q k
  IxQ.putMany q k xs
  ys <- IxQ.read q k
  onComplete ([] == ys)
