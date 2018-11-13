module Test.Main.Queue.One where

import Prelude
import Queue.One as One
import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as ArrayNE
import Effect (Effect)
import Effect.Ref (Ref)
import Effect.Ref as Ref


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
