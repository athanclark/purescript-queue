module Test.Main.Queue where

import Prelude
import Queue as Q
import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as ArrayNE
import Effect (Effect)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Effect.Timer (setTimeout)


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
