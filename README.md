# PureScript-Queue

The pub/sub model captures a simple concept - assign "handlers" to an event manager of
some kind, and delegate messages to those handlers by issuing events.

This library is an implementation of a trivial pub/sub model for PureScript:

```purescript
import Queue (newQueue, onQueue, putQueue)

main = do
  q <- newQueue
  
  onQueue q \x -> logShow x
  
  putQueue q 1
  putQueue q 2
```

It tries to immitate similar functionality to `Chan`s from Haskell; but because
JavaScript is single-threaded, we have to be creative.

The `Queue` module provides
a set-like perspective on handlers - you can additively register individual event
handlers, but can only clear them all at once. The `IxQueue` module treats handlers
as a _mapping_ (a `StrMap` specifically) instead, allowing you to distinguish which
handler receives a message (opposed to broadcasting), or descrepently remove a
single handler from the map.

The behavior of this library is such that - if no handlers are registered, then
store pending messages first-in-first-out until one is available. Similarly
for `IxQueue` - if the _specific_ handler isn't available, attempt to use the
default handler if it exists - if not, store the message for the specific handler
(or, in the case of broadcasts, for the default). Unfortunately the `IxQueue`
theory isn't very robust or well-thought out - if you'd like to see a redesign,
please don't hesitate to hack!


## Async

This library's main goal was to aid in cross-site interopability - almost localized
RPC mechanisms - through the `Queue.Aff` and `IxQueue.Aff` modules, we can treat
message passing at a higher level as _procedure invocations_:

```purescript
import Queue.Aff (newIOQueues, registerSync, callAsync)
import Control.Monad.Aff (runAff_)

main = do
  io <- newIOQueues
  
  registerSync io $ \i -> do
    log $ "input: " <> show i
    let o = i + 1
    log $ "incremented: " <> show o
    pure o
    
  runAff_ logShow $ do
    result <- callAsync io 20
    liftEff $ log $ "Wow that was a super complicated delegated computation! Result: " <> show result
```
