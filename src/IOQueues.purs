-- | Promotes a set of Queues to represent the input and output of an `Effect`ful function, decoupled
-- | from it's definition. It brings the function's invocation to the `Aff` context, but warning:
-- | invocations are not cancelable.
module IOQueues where


-- | Represents an asynchronously invokable function `input -> Aff output`
newtype IOQueues q input output = IOQueues
  { input :: q (read :: READ) input
  , output :: q (write :: WRITE) output
  }


new :: forall q input output. Effect q -> Effect (IOQueues input output)
new mkQ = do
  input <- readOnly <$> mkQ
  output <- writeOnly <$> mkQ
  pure (IOQueues {input,output})


-- | Invoke the queue in `Aff`.
callAsync :: forall q input output
           . IOQueues input output
          -> input
          -> Aff output
callAsync qs x = makeAff \resolve ->
  nonCanceler <$ callAsyncEff qs (resolve <<< Right) x


-- | Invoke the queue in `Eff`
callAsyncEff :: forall q input output
              . IOQueues q input output
             -> Handler output
             -> input
             -> Effect Unit
callAsyncEff (IOQueues {input,output}) f x = do
  Queue.once (allowReading output) f
  Queue.put (allowWriting input) x


-- | For binding the receiver
registerSync :: forall q input output
              . IOQueues q input output
             -> (input -> Effect output)
             -> Effect Unit
registerSync (IOQueues {input,output}) f =
  Queue.on input \x -> f x >>= Queue.put output


-- | Bind a receiver only once
registerSyncOnce :: forall q input output
                  . IOQueues q input output
                 -> (input -> Effect output)
                 -> Effect Unit
registerSyncOnce (IOQueues {input,output}) f =
  Queue.once input \x -> f x >>= Queue.put output
