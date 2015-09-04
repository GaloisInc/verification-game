module NumberLiterals (prettyInteger) where

twoPowHtml :: Int -> String
twoPowHtml n = "2<sup><small>" ++ show n ++ "</small></sup>"

minus :: String
minus = " &#8722; "

showWithOp :: Integer -> String
showWithOp x
  = case compare x 0 of
      LT -> minus ++ show (negate x)
      EQ -> ""
      GT -> " + " ++ show x

-- | Generate a pretty, signed-base 2^16 sum representation in HTML of
-- an arbitrary signed integer.
prettyInteger :: Integer -> String
prettyInteger x        =
  case intLogTwo q of
    Just p  -> let (powNeg,r')
                     | x < 0 = ("-", negate (r - 32768))
                     | otherwise = ("", r - 32768)
               in powNeg ++ twoPowHtml (16+p) ++ showWithOp r'
    Nothing -> show x
  where
  (q,r) = (abs x + 32768) `quotRem` 65536

intLogTwo :: Integer -> Maybe Int
intLogTwo x0
  | x0 <= 0   = Nothing
  | otherwise = go 0 x0
  where
  go acc _ | seq acc False = undefined
  go acc 1 = Just acc
  go acc x
    | odd x = Nothing
    | otherwise = go (acc+1) (x`quot`2)
