module Bartleby.SmokeSpec (spec) where

import Test.Hspec

spec :: Spec
spec = describe "smoke" $ do
  it "builds and runs a test" $
    (1 + 1 :: Int) `shouldBe` 2
