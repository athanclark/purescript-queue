module Test.Main.Queue where

import Prelude
import Queue as Q
import Data.Maybe (Maybe (..))
import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as ArrayNE
import Effect (Effect)
import Effect.Random (randomInt)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Effect.Timer (setTimeout)
import Partial.Unsafe (unsafePartial)


putManyAfterOnSync :: forall a
                    . Eq a
                   => NonEmptyArray a
                   -> (Boolean -> Effect Unit)
                   -> Effect Unit
putManyAfterOnSync xs onComplete = do
  q <- Q.new
  (obtained :: Ref (Array a)) <- Ref.new []
  Q.on q \x -> do
    newXs <- Ref.modify (\ys -> ys `Array.snoc` x) obtained
    if Array.length newXs == ArrayNE.length xs
       then onComplete (newXs == ArrayNE.toArray xs)
       else pure unit
  Q.putMany q xs


putManyBroadcastsAfterOnSync :: forall a
                              . Eq a
                             => NonEmptyArray a
                             -> (Boolean -> Effect Unit)
                             -> Effect Unit
putManyBroadcastsAfterOnSync xs onComplete = do
  q <- Q.new
  n <- randomInt 1 10
  (obtained :: Ref (Array (Array a))) <- Ref.new (Array.replicate n [])
  let replicateM :: forall m. Monad m => Int -> (Int -> m Unit) -> m Unit
      replicateM n' x
        | n' == 1 = x n'
        | otherwise = do
          x n'
          replicateM (n' - 1) x
  replicateM n $ \i -> Q.on q $ \x -> do
    let go' zs = zs `Array.snoc` x
        go ys = unsafePartial $ case Array.modifyAt (i - 1) go' ys of
                  Just ys' -> ys'
    newXs <- Ref.modify go obtained
    if Array.all (\x -> Array.length x == ArrayNE.length xs) newXs
       then onComplete (Array.all (\z -> z == ArrayNE.toArray xs) newXs)
       else pure unit
  Q.putMany q xs


putManyBeforeOnSync :: forall a
                     . Eq a
                    => NonEmptyArray a
                    -> (Boolean -> Effect Unit)
                    -> Effect Unit
putManyBeforeOnSync xs onComplete = do
  q <- Q.new
  (obtained :: Ref (Array a)) <- Ref.new []
  Q.putMany q xs
  Q.on q \x -> do
    newXs <- Ref.modify (\ys -> ys `Array.snoc` x) obtained
    if Array.length newXs == ArrayNE.length xs
       then onComplete (newXs == ArrayNE.toArray xs)
       else pure unit


-- | Doesn't work because the first handler is in a race condition with adding another.
putManyBroadcastsBeforeOnSync :: forall a
                              . Eq a
                             => NonEmptyArray a
                             -> (Boolean -> Effect Unit)
                             -> Effect Unit
putManyBroadcastsBeforeOnSync xs onComplete = do
  q <- Q.new
  n <- randomInt 1 10
  (obtained :: Ref (Array (Array a))) <- Ref.new (Array.replicate n [])
  Q.putMany q xs
  let replicateM :: forall m. Monad m => Int -> (Int -> m Unit) -> m Unit
      replicateM n' x
        | n' == 1 = x n'
        | otherwise = do
          x n'
          replicateM (n' - 1) x
  replicateM n $ \i -> Q.on q $ \x -> do
    let go' zs = zs `Array.snoc` x
        go ys = unsafePartial $ case Array.modifyAt (i - 1) go' ys of
                  Just ys' -> ys'
    newXs <- Ref.modify go obtained
    if Array.all (\x -> Array.length x == ArrayNE.length xs) newXs
       then onComplete (Array.all (\z -> z == ArrayNE.toArray xs) newXs)
       else pure unit


putManyAfterOnceAtLeastOnce :: forall a
                             . Eq a
                            => NonEmptyArray a
                            -> (Boolean -> Effect Unit)
                            -> Effect Unit
putManyAfterOnceAtLeastOnce xs onComplete = do
  q <- Q.new
  Q.once q \x -> onComplete (x == ArrayNE.head xs)
  Q.putMany q xs


putManyAfterOnceOnlyOnce :: forall a
                          . Eq a
                         => NonEmptyArray a
                         -> (Boolean -> Effect Unit)
                         -> Effect Unit
putManyAfterOnceOnlyOnce xs onComplete = do
  q <- Q.new
  (valuesObtained :: Ref (Array a)) <- Ref.new []
  Q.once q \x -> void (Ref.modify (\ys -> ys `Array.snoc` x) valuesObtained)
  Q.putMany q xs
  void $ setTimeout 100 do
    vs <- Ref.read valuesObtained
    onComplete (vs == [ArrayNE.head xs])


readIdempotent :: forall a
                . Eq a
               => NonEmptyArray a
               -> (Boolean -> Effect Unit)
               -> Effect Unit
readIdempotent xs onComplete = do
  q <- Q.new
  Q.putMany q xs
  r1 <- Q.read q
  r2 <- Q.read q
  onComplete (r1 == r2)


takeIdentity :: forall a
              . Eq a
             => NonEmptyArray a
             -> (Boolean -> Effect Unit)
             -> Effect Unit
takeIdentity xs onComplete = do
  q <- Q.new
  Q.putMany q xs
  ys <- Q.take q
  onComplete (ArrayNE.toArray xs == ys)


take2ndIdempotent :: forall a
                   . Eq a
                  => NonEmptyArray a
                  -> (Boolean -> Effect Unit)
                  -> Effect Unit
take2ndIdempotent xs onComplete = do
  q <- Q.new
  Q.putMany q xs
  _ <- Q.take q
  ys1 <- Q.take q
  ys2 <- Q.take q
  onComplete (ys1 == ys2 && ys2 == [])


delPendingIdentity :: forall a
                    . Eq a
                   => NonEmptyArray a
                   -> (Boolean -> Effect Unit)
                   -> Effect Unit
delPendingIdentity xs onComplete = do
  q <- Q.new
  Q.drain q
  Q.del q
  Q.putMany q xs
  ys <- Q.read q
  onComplete (ArrayNE.toArray xs == ys)


drainConsumes :: forall a
               . Eq a
              => NonEmptyArray a
              -> (Boolean -> Effect Unit)
              -> Effect Unit
drainConsumes xs onComplete = do
  q <- Q.new
  Q.drain q
  Q.putMany q xs
  ys <- Q.read q
  onComplete ([] == ys)
