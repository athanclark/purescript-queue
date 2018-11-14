module Test.Main where

import Test.Main.Queue.One as OneTest
import Test.QuickCheck (arbitrary)
import Test.QuickCheck.Gen as QC

import Prelude
import Data.Enum (succ)
import Data.Either (Either (..))
import Data.Maybe (Maybe (Just))
import Data.Traversable (traverse_)
import Data.Array.NonEmpty (NonEmptyArray)
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Aff (Aff, makeAff, nonCanceler, runAff_)
import Effect.Exception (throwException, error)
import Effect.Console (log, warn)
import Effect.Ref as Ref
import Partial.Unsafe (unsafePartial)


test :: (forall a. Eq a => NonEmptyArray a -> (Boolean -> Effect Unit) -> Effect Unit)
     -> Aff Unit
test go = makeAff \resolve -> do
  testCases <- QC.randomSample' 100 (arbitrary :: QC.Gen (NonEmptyArray Int))
  successes <- Ref.new 0
  let report :: Boolean -> Effect Unit
      report success
        | success = do
          let inc :: Int -> Int
              inc x = unsafePartial $ case succ x of
                Just y -> y
          new <- Ref.modify inc successes
          if new == 100
            then do
              log "success!"
              resolve (Right unit)
            else pure unit
        | otherwise = resolve $ Left $ error "failure!"
  traverse_ (\testCase -> go testCase report) testCases
  pure nonCanceler

main :: Effect Unit
main =
  let resolve eX = case eX of
        Left e -> throwException e
        Right _ -> pure unit
  in  runAff_ resolve do
        liftEffect $ log "Queue.One.putMany after Queue.One.on"
        test OneTest.putManyAfterOnSync
        liftEffect $ log "Queue.One.putMany before Queue.One.on"
        test OneTest.putManyBeforeOnSync
        liftEffect $ log "Queue.One.putMany after Queue.One.once at least once"
        test OneTest.putManyAfterOnceAtLeastOnce
        liftEffect $ log "Queue.One.putMany after Queue.One.once only once"
        test OneTest.putManyAfterOnceOnlyOnce
        liftEffect $ log "Queue.One.read idempotent"
        test OneTest.readIdempotent
        liftEffect $ log "Queue.One.take identity"
        test OneTest.takeIdentity
        liftEffect $ log "Queue.One.take 2nd idempotent"
        test OneTest.take2ndIdempotent
        liftEffect $ log "Queue.One.del pending identity"
        test OneTest.delPendingIdentity
        liftEffect $ log "Queue.One.drain consumes"
        test OneTest.drainConsumes
