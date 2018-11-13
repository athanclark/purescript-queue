module Test.Main.Queue.One where

import Prelude
import Queue.One as One
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
  q <- One.new
  (obtained :: Ref (Array a)) <- Ref.new []
  One.on q \x -> do
    newXs <- Ref.modify (\ys -> ys `Array.snoc` x) obtained
    if Array.length newXs == ArrayNE.length xs
       then onComplete (newXs == ArrayNE.toArray xs)
       else pure unit
  One.putMany q xs


putManyBeforeOnSync :: forall a
                     . Eq a
                    => NonEmptyArray a
                    -> (Boolean -> Effect Unit)
                    -> Effect Unit
putManyBeforeOnSync xs onComplete = do
  q <- One.new
  (obtained :: Ref (Array a)) <- Ref.new []
  One.putMany q xs
  One.on q \x -> do
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
  q <- One.new
  One.once q \x -> onComplete (x == ArrayNE.head xs)
  One.putMany q xs


putManyAfterOnceOnlyOnce :: forall a
                          . Eq a
                         => NonEmptyArray a
                         -> (Boolean -> Effect Unit)
                         -> Effect Unit
putManyAfterOnceOnlyOnce xs onComplete = do
  q <- One.new
  (valuesObtained :: Ref (Array a)) <- Ref.new []
  One.once q \x -> void (Ref.modify (\ys -> ys `Array.snoc` x) valuesObtained)
  One.putMany q xs
  void $ setTimeout 100 do
    vs <- Ref.read valuesObtained
    onComplete (vs == [ArrayNE.head xs])


readIdempotent :: forall a
                . Eq a
               => NonEmptyArray a
               -> (Boolean -> Effect Unit)
               -> Effect Unit
readIdempotent xs onComplete = do
  q <- One.new
  One.putMany q xs
  r1 <- One.read q
  r2 <- One.read q
  onComplete (r1 == r2)


takeIdentity :: forall a
              . Eq a
             => NonEmptyArray a
             -> (Boolean -> Effect Unit)
             -> Effect Unit
takeIdentity xs onComplete = do
  q <- One.new
  One.putMany q xs
  ys <- One.take q
  onComplete (ArrayNE.toArray xs == ys)


take2ndIdempotent :: forall a
                   . Eq a
                  => NonEmptyArray a
                  -> (Boolean -> Effect Unit)
                  -> Effect Unit
take2ndIdempotent xs onComplete = do
  q <- One.new
  One.putMany q xs
  _ <- One.take q
  ys1 <- One.take q
  ys2 <- One.take q
  onComplete (ys1 == ys2 && ys2 == [])


delPendingIdentity :: forall a
                    . Eq a
                   => NonEmptyArray a
                   -> (Boolean -> Effect Unit)
                   -> Effect Unit
delPendingIdentity xs onComplete = do
  q <- One.new
  One.drain q
  One.del q
  One.putMany q xs
  ys <- One.read q
  onComplete (ArrayNE.toArray xs == ys)


drainConsumes :: forall a
               . Eq a
              => NonEmptyArray a
              -> (Boolean -> Effect Unit)
              -> Effect Unit
drainConsumes xs onComplete = do
  q <- One.new
  One.drain q
  One.putMany q xs
  ys <- One.read q
  onComplete ([] == ys)
