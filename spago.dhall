{-
Welcome to a Spago project!
You can edit this file as you like.
-}
{ name = "queue"
, dependencies =
  [ "aff"
  , "avar"
  , "console"
  , "effect"
  , "foreign-object"
  , "prelude"
  , "refs"
  ]
, packages = ./packages.dhall
, sources = [ "src/**/*.purs" ]
, license = "BSD-3-Clause"
, repository = "https://github.com/athanclark/purescript-queue.git"
}
