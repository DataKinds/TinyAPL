{-# LANGUAGE FlexibleContexts, LambdaCase, NegativeLiterals #-}

module TinyAPL.Functions where

import TinyAPL.ArrayFunctionOperator
import TinyAPL.Error
import TinyAPL.Random
import TinyAPL.Util

import Control.Monad.Except (MonadError)
import qualified TinyAPL.Complex as Cx
import TinyAPL.Complex ( Complex((:+)) )
import Data.Char (ord, chr)
import Data.Maybe (fromJust, fromMaybe)
import Data.List (elemIndex, genericLength, genericTake, genericDrop, genericReplicate, nub, genericIndex, sortOn, sort, find)
import Numeric.Natural (Natural)
import Control.Monad
import Control.Monad.State (MonadIO)
import Data.Ord (Down(..))
import qualified Data.Matrix as M
import qualified TinyAPL.Gamma.Gamma as Gamma
import Data.Foldable (foldlM, foldrM)

-- * Functions

expectedNumber = DomainError "Expected number"
expectedReal = DomainError "Expected real"
expectedInteger = DomainError "Expected integer"
expectedNatural = DomainError "Expected natural"
expectedBool = DomainError "Expected boolean"

conjugate :: MonadError Error m => ScalarValue -> m ScalarValue
conjugate (Number y) = pure $ Number $ Cx.conjugate y
conjugate _ = throwError expectedNumber

conjugate' :: MonadError Error m => Array -> m Array
conjugate' = scalarMonad conjugate

add :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
add (Number x) (Number y) = pure $ Number $ x + y
add (Number x) (Character y) = do
  x' <- asInt expectedInteger x
  pure $ Character $ chr $ ord y + x'
add (Character x) (Number y) = do
  y' <- asInt expectedInteger y
  pure $ Character $ chr $ ord x + y'
add _ _ = throwError expectedNumber

add' :: MonadError Error m => Array -> Array -> m Array
add' = scalarDyad add

neg :: MonadError Error m => ScalarValue -> m ScalarValue
neg (Number y) = pure $ Number $ negate y
neg _ = throwError expectedNumber

neg' :: MonadError Error m => Array -> m Array
neg' = scalarMonad neg

sub :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
sub (Number x) (Number y) = pure $ Number $ x - y
sub (Character x) (Number y) = do
  y' <- asInt expectedInteger y
  pure $ Character $ chr $ ord x - y'
sub (Character x) (Character y) = pure $ Number $ fromInteger . toInteger $ ord x - ord y
sub _ _ = throwError expectedNumber

sub' :: MonadError Error m => Array -> Array -> m Array
sub' = scalarDyad sub

sign :: MonadError Error m => ScalarValue -> m ScalarValue
sign (Number y) = pure $ Number $ signum y
sign _ = throwError expectedNumber

sign' :: MonadError Error m => Array -> m Array
sign' = scalarMonad sign

times :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
times (Number x) (Number y) = pure $ Number $ x * y
times _ _ = throwError expectedNumber

times' :: MonadError Error m => Array -> Array -> m Array
times' = scalarDyad times

reciprocal :: MonadError Error m => ScalarValue -> m ScalarValue
reciprocal (Number 0) = throwError $ DomainError "Divide by zero"
reciprocal (Number y) = pure $ Number $ recip y
reciprocal _ = throwError expectedNumber

reciprocal' :: MonadError Error m => Array -> m Array
reciprocal' = scalarMonad reciprocal

divide :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
divide (Number 0) (Number 0) = pure $ Number 1
divide _ (Number 0) = throwError $ DomainError "Divide by zero"
divide (Number x) (Number y) = pure $ Number $ x / y
divide _ _ = throwError expectedNumber

divide' :: MonadError Error m => Array -> Array -> m Array
divide' = scalarDyad divide

ePow :: MonadError Error m => ScalarValue -> m ScalarValue
ePow (Number y) = pure $ Number $ exp y
ePow _ = throwError expectedNumber

ePow' :: MonadError Error m => Array -> m Array
ePow' = scalarMonad ePow

pow :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
pow (Number x) (Number y) = case asNat (DomainError "") y of
  Left _ -> pure $ Number $ x ** y
  Right y' -> pure $ Number $ x ^ y'
pow _ _ = throwError expectedNumber

pow' :: MonadError Error m => Array -> Array -> m Array
pow' = scalarDyad pow

ln :: MonadError Error m => ScalarValue -> m ScalarValue
ln (Number 0) = throwError $ DomainError "Logarithm of zero"
ln (Number y) = pure $ Number $ Prelude.log y
ln _ = throwError expectedNumber

ln' :: MonadError Error m => Array -> m Array
ln' = scalarMonad ln

log :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
log (Number 1) (Number 1) = pure $ Number 1
log (Number 1) _ = throwError $ DomainError "Logarithm base one"
log _ (Number 0) = throwError $ DomainError "Logarithm of zero"
log (Number x) (Number y) = pure $ Number $ logBase x y
log _ _ = throwError expectedNumber

log' :: MonadError Error m => Array -> Array -> m Array
log' = scalarDyad TinyAPL.Functions.log

squareRoot :: MonadError Error m => ScalarValue -> m ScalarValue
squareRoot (Number y) = pure $ Number $ sqrt y
squareRoot _ = throwError expectedNumber

squareRoot' :: MonadError Error m => Array -> m Array
squareRoot' = scalarMonad squareRoot

root :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
root (Number x) (Number y) = pure $ Number $ y ** recip x
root _ _ = throwError expectedNumber

root' :: MonadError Error m => Array -> Array -> m Array
root' = scalarDyad root

matrixInverse :: MonadError Error m => M.Matrix (Complex Double) -> m (M.Matrix (Complex Double))
matrixInverse y = do
  let hermitian = fmap Cx.conjugate . M.transpose
  case M.inverse (hermitian y * y) of
    Left err -> throwError $ DomainError err
    Right r -> pure $ r * hermitian y

matrixInverse' :: MonadError Error m => Array -> m Array
matrixInverse' = atRank1 (\y -> do
  r <- rank y
  mat <- asMatrix (DomainError "") y >>= mapM (asNumber (DomainError "Matrix inverse argument must be numeric"))
  inv <- fmap Number <$> matrixInverse (if r < 2 then M.transpose mat else mat)
  if r < 2 then pure $ Array (arrayShape y) (M.toList inv)
  else pure $ matrix inv) 2

matrixDivide :: MonadError Error m => M.Matrix (Complex Double) -> M.Matrix (Complex Double) -> m (M.Matrix (Complex Double))
matrixDivide x y = (* x) <$> matrixInverse y

matrixDivide' :: MonadError Error m => Array -> Array -> m Array
matrixDivide' = atRank2 (\x y -> do
  x' <- asMatrix (DomainError "") x >>= mapM (asNumber (DomainError "Matrix divide arguments must be numeric"))
  y' <- asMatrix (DomainError "") y >>= mapM (asNumber (DomainError "Matrix divide arguments must be numeric")) 
  matrix . fmap Number <$> matrixDivide x' y') (2, 2)

floor :: MonadError Error m => ScalarValue -> m ScalarValue
floor (Number y) = pure $ Number $ complexFloor y
floor _ = throwError expectedNumber

floor' :: MonadError Error m => Array -> m Array
floor' = scalarMonad TinyAPL.Functions.floor

ceil :: MonadError Error m => ScalarValue -> m ScalarValue
ceil (Number y) = pure $ Number $ complexCeiling y
ceil _ = throwError expectedNumber

ceil' :: MonadError Error m => Array -> m Array
ceil' = scalarMonad ceil

round :: MonadError Error m => ScalarValue -> m ScalarValue
round (Number y) = pure $ Number $ componentFloor $ y + (0.5 :+ 0.5)
round _ = throwError expectedNumber

round' :: MonadError Error m => Array -> m Array
round' = scalarMonad TinyAPL.Functions.round

roundTo :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
roundTo = commute $ leftFork (TinyAPL.Functions.round `atop` divide) times

roundTo' :: MonadError Error m => Array -> Array -> m Array
roundTo' = scalarDyad roundTo

min :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
min x y = pure $ Prelude.min x y

min' :: MonadError Error m => Array -> Array -> m Array
min' = scalarDyad TinyAPL.Functions.min

max :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
max x y = pure $ Prelude.max x y

max' :: MonadError Error m => Array -> Array -> m Array
max' = scalarDyad TinyAPL.Functions.max

lcm :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
lcm (Number x) (Number y) = pure $ Number $ complexLCM x y
lcm _ _ = throwError expectedNumber

lcm' :: MonadError Error m => Array -> Array -> m Array
lcm' = scalarDyad TinyAPL.Functions.lcm

gcd :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
gcd (Number x) (Number y) = pure $ Number $ complexGCD x y
gcd _ _ = throwError expectedNumber

gcd' :: MonadError Error m => Array -> Array -> m Array
gcd' = scalarDyad TinyAPL.Functions.gcd

nand :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
nand (Number 0) (Number 0) = pure $ Number 1
nand (Number 0) (Number 1) = pure $ Number 1
nand (Number 1) (Number 0) = pure $ Number 1
nand (Number 1) (Number 1) = pure $ Number 0
nand _ _ = throwError expectedBool

nand' :: MonadError Error m => Array -> Array -> m Array
nand' = scalarDyad nand

nor :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
nor (Number 0) (Number 0) = pure $ Number 1
nor (Number 0) (Number 1) = pure $ Number 0
nor (Number 1) (Number 0) = pure $ Number 0
nor (Number 1) (Number 1) = pure $ Number 0
nor _ _ = throwError expectedBool

nor' :: MonadError Error m => Array -> Array -> m Array
nor' = scalarDyad nor

imaginary :: MonadError Error m => ScalarValue -> m ScalarValue
imaginary (Number y) = pure $ Number $ y * i
imaginary _ = throwError expectedNumber

imaginary' :: MonadError Error m => Array -> m Array
imaginary' = scalarMonad imaginary

cartesian :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
cartesian (Number x) (Number y) = pure $ Number $ x + y * i
cartesian _ _ = throwError expectedNumber

cartesian' :: MonadError Error m => Array -> Array -> m Array
cartesian' = scalarDyad cartesian

unitPolar :: MonadError Error m => ScalarValue -> m ScalarValue
unitPolar (Number y) = pure $ Number $ exp $ i * y
unitPolar _ = throwError expectedNumber

unitPolar' :: MonadError Error m => Array -> m Array
unitPolar' = scalarMonad unitPolar

polar :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
polar (Number x) (Number y) = pure $ Number $ x * exp (i * y)
polar _ _ = throwError expectedNumber

polar' :: MonadError Error m => Array -> Array -> m Array
polar' = scalarDyad polar

abs :: MonadError Error m => ScalarValue -> m ScalarValue
abs (Number y) = pure $ Number $ Prelude.abs y
abs _ = throwError expectedNumber

abs' :: MonadError Error m => Array -> m Array
abs' = scalarMonad TinyAPL.Functions.abs

remainder :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
remainder (Number x) (Number y) = pure $ Number $ complexRemainder x y
remainder _ _ = throwError expectedNumber

remainder' :: MonadError Error m => Array -> Array -> m Array
remainder' = scalarDyad remainder

phase :: MonadError Error m => ScalarValue -> m ScalarValue
phase (Number y) = pure $ Number $ Cx.phase y :+ 0
phase _ = throwError expectedNumber

phase' :: MonadError Error m => Array -> m Array
phase' = scalarMonad phase

real :: MonadError Error m => ScalarValue -> m ScalarValue
real (Number y) = pure $ Number $ Cx.realPart y :+ 0
real _ = throwError expectedNumber

real' :: MonadError Error m => Array -> m Array
real' = scalarMonad real

imag :: MonadError Error m => ScalarValue -> m ScalarValue
imag (Number y) = pure $ Number $ Cx.imagPart y :+ 0
imag _ = throwError expectedNumber

imag' :: MonadError Error m => Array -> m Array
imag' = scalarMonad imag

arctan :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
arctan (Number x) (Number y) = pure $ Number $ Cx.phase (y + x * i) :+ 0
arctan _ _ = throwError expectedNumber

arctan' :: MonadError Error m => Array -> Array -> m Array
arctan' = scalarDyad arctan

not :: MonadError Error m => ScalarValue -> m ScalarValue
not (Number y) = pure $ Number $ 1 - y
not _ = throwError expectedNumber

not' :: MonadError Error m => Array -> m Array
not' = scalarMonad TinyAPL.Functions.not

increment :: MonadError Error m => ScalarValue -> m ScalarValue
increment (Number y) = pure $ Number $ y + 1
increment (Character y) = pure $ Character $ chr $ ord y + 1
increment _ = throwError expectedNumber

increment' :: MonadError Error m => Array -> m Array
increment' = scalarMonad increment

decrement :: MonadError Error m => ScalarValue -> m ScalarValue
decrement (Number y) = pure $ Number $ y - 1
decrement (Character '\0') = pure $ Character '\0'
decrement (Character y) = pure $ Character $ chr $ ord y - 1
decrement _ = throwError expectedNumber

decrement' :: MonadError Error m => Array -> m Array
decrement' = scalarMonad decrement

span :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
span (Number x) (Number y) = pure $ Number $ 1 + x - y
span _ _ = throwError expectedNumber

span' :: MonadError Error m => Array -> Array -> m Array
span' = scalarDyad TinyAPL.Functions.span

equal :: MonadError Error m => ScalarValue -> ScalarValue -> m Bool
equal x y = pure $ x == y

equal' :: MonadError Error m => Array -> Array -> m Array
equal' = scalarDyad (fmap boolToScalar .: equal)

notEqual :: MonadError Error m => ScalarValue -> ScalarValue -> m Bool
notEqual x y = pure $ x /= y

notEqual' :: MonadError Error m => Array -> Array -> m Array
notEqual' = scalarDyad (fmap boolToScalar .: notEqual)

less :: MonadError Error m => ScalarValue -> ScalarValue -> m Bool
less x y = pure $ x < y

less' :: MonadError Error m => Array -> Array -> m Array
less' = scalarDyad (fmap boolToScalar .: less)

lessEqual :: MonadError Error m => ScalarValue -> ScalarValue -> m Bool
lessEqual x y = pure $ x <= y

lessEqual' :: MonadError Error m => Array -> Array -> m Array
lessEqual' = scalarDyad (fmap boolToScalar .: lessEqual)

greaterEqual :: MonadError Error m => ScalarValue -> ScalarValue -> m Bool
greaterEqual x y = pure $ x >= y

greaterEqual' :: MonadError Error m => Array -> Array -> m Array
greaterEqual' = scalarDyad (fmap boolToScalar .: greaterEqual)

greater :: MonadError Error m => ScalarValue -> ScalarValue -> m Bool
greater x y = pure $ x > y

greater' :: MonadError Error m => Array -> Array -> m Array
greater' = scalarDyad (fmap boolToScalar .: greater)

precedes :: MonadError Error m => Array -> Array -> m Bool
precedes x y = pure $ x < y

precedes' :: MonadError Error m => Array -> Array -> m Array
precedes' x y = scalar . boolToScalar <$> precedes x y

precedesOrIdentical :: MonadError Error m => Array -> Array -> m Bool
precedesOrIdentical x y = pure $ x <= y

precedesOrIdentical' :: MonadError Error m => Array -> Array -> m Array
precedesOrIdentical' x y = scalar . boolToScalar <$> precedesOrIdentical x y

succeedsOrIdentical :: MonadError Error m => Array -> Array -> m Bool
succeedsOrIdentical x y = pure $ x >= y

succeedsOrIdentical' :: MonadError Error m => Array -> Array -> m Array
succeedsOrIdentical' x y = scalar . boolToScalar <$> succeedsOrIdentical x y

succeeds :: MonadError Error m => Array -> Array -> m Bool
succeeds x y = pure $ x > y

succeeds' :: MonadError Error m => Array -> Array -> m Array
succeeds' x y = scalar . boolToScalar <$> succeeds x y

minimal :: MonadError Error m => Array -> Array -> m Array
minimal x y = pure $ Prelude.min x y

maximal :: MonadError Error m => Array -> Array -> m Array
maximal x y = pure $ Prelude.max x y

identical :: MonadError Error m => Array -> Array -> m Bool
identical x y = pure $ x == y

identical' :: MonadError Error m => Array -> Array -> m Array
identical' x y = scalar . boolToScalar <$> identical x y

notIdentical :: MonadError Error m => Array -> Array -> m Bool
notIdentical x y = pure $ x /= y

notIdentical' :: MonadError Error m => Array -> Array -> m Array
notIdentical' x y = scalar . boolToScalar <$> notIdentical x y

tally :: MonadError Error m => Array -> m Natural
tally y = pure $ genericLength $ majorCells y

tally' :: MonadError Error m => Array -> m Array
tally' y = scalar . Number . fromInteger . toInteger <$> tally y

nubSieve :: (Ord a, MonadError Error m) => [a] -> m [Bool]
nubSieve ys = pure $ zipWith (\c idx -> fromJust (c `elemIndex` ys) == idx) ys [0..]

nubSieve' :: MonadError Error m => Array -> m Array
nubSieve' arr = do
  nub <- nubSieve $ majorCells arr
  pure $ vector $ boolToScalar <$> nub

shape :: MonadError Error m => Array -> m [Natural]
shape y = pure $ arrayShape y

shape' :: MonadError Error m => Array -> m Array
shape' arr = do
  sh <- shape arr
  pure $ vector $ Number . fromInteger . toInteger <$> sh

reshape :: MonadError Error m => [Integer] -> Array -> m Array
reshape shape arr@(Array _ xs) = do
  let negative = TinyAPL.Util.count (< 0) shape
  if negative == 0 then case arrayReshaped (fromInteger . toInteger <$> shape) xs of
    Nothing -> throwError $ DomainError "Cannot reshape an empty array to a non-empty array"
    Just res -> pure res
  else if negative == 1 && -1 `elem` shape then do
    let bound = genericLength xs
    let known = product $ filter (>= 0) shape
    if known == 0 then throwError $ DomainError "Shape cannot contain both 0 and -1"
    else if bound `mod` known /= 0 then throwError $ DomainError "Shape is not a multiple of the bound of the array"
    else reshape ((\x -> if x == -1 then bound `div` known else x) <$> shape) arr
  else throwError $ DomainError "Invalid shape"

reshape' :: MonadError Error m => Array -> Array -> m Array
reshape' sh arr = do
  let err = DomainError "Shape must be an integer vector"
  shape <- asVector err sh >>= mapM (asNumber err >=> asInt err)
  reshape shape arr

rank :: MonadError Error m => Array -> m Natural
rank = pure . arrayRank

rank' :: MonadError Error m => Array -> m Array
rank' arr = scalar . Number . fromInteger . toInteger <$> rank arr

promote :: MonadError Error m => Array -> m Array
promote arr = reshape (1 : map toInteger (arrayShape arr)) arr

demote :: MonadError Error m => Array -> m Array
demote arr = case (toInteger <$> arrayShape arr, arrayContents arr) of
  ([], _) -> pure arr
  ([_], []) -> throwError $ DomainError "Demote empty vector to scalar"
  ([_], c:_) -> pure $ scalar c
  (a:b:ss, _) -> reshape (a * b : ss) arr

rerank :: MonadError Error m => Natural -> Array -> m Array
rerank n arr =
  if arrayRank arr == n then pure arr
  else if arrayRank arr > n then demote arr >>= rerank n
  else promote arr >>= rerank n

rerank' :: MonadError Error m => Array -> Array -> m Array
rerank' narr arr = do
  let err = DomainError "Rerank left argument must be a scalar natural"
  n <- asScalar err narr >>= asNumber err >>= asNat err
  rerank n arr

ravel :: MonadError Error m => Array -> m [ScalarValue]
ravel arr = pure $ arrayContents arr

ravel' :: MonadError Error m => Array -> m Array
ravel' = fmap vector . ravel

enlist :: MonadError Error m => Array -> m [ScalarValue]
enlist (Array [] [Box a]) = enlist a
enlist (Array [] sc) = pure sc
enlist (Array _ cs) = concat <$> mapM (enlist . fromScalar) cs

enlist' :: MonadError Error m => Array -> m Array
enlist' y = vector <$> enlist y

depth :: MonadError Error m => Array -> m Natural
depth arr = pure $ arrayDepth arr

depth' :: MonadError Error m => Array -> m Array
depth' = fmap (scalar . Number . fromInteger . toInteger) . depth

reverse :: MonadError Error m => [a] -> m [a]
reverse = pure . Prelude.reverse

reverse' :: MonadError Error m => Array -> m Array
reverse' = onMajorCells TinyAPL.Functions.reverse

rotate :: MonadError Error m => [Integer] -> Array -> m Array
rotate [] xs = pure xs
rotate (r:rs) xs = fromMajorCells . TinyAPL.Util.rotate r <$> mapM (TinyAPL.Functions.rotate rs) (majorCells xs)

rotate' :: MonadError Error m => Array -> Array -> m Array
rotate' rot arr = do
  let err = DomainError "Rotate left argument must be an integer vector or scalar"
  rs <- asVector err rot >>= mapM (asNumber err >=> asInt err)
  TinyAPL.Functions.rotate rs arr

take :: MonadError Error m => [Integer] -> Array -> m Array
take [] xs = pure xs
take (t:ts) xs = let
  take' c = if c < 0 then Prelude.reverse . genericTake (negate c) . Prelude.reverse else genericTake c
  in fromMajorCells . take' t <$> mapM (TinyAPL.Functions.take ts) (majorCells xs)

take' :: MonadError Error m => Array -> Array -> m Array
take' tak arr = do
  let err = DomainError "Take left argument must be an integer vector"
  ts <- asVector err tak >>= mapM (asNumber err >=> asInt err)
  TinyAPL.Functions.take ts arr

drop :: MonadError Error m => [Integer] -> Array -> m Array
drop [] xs = pure xs
drop (d:ds) xs = let
  drop' c = if c < 0 then Prelude.reverse . genericDrop (negate c) . Prelude.reverse else genericDrop c
  in fromMajorCells . drop' d <$> mapM (TinyAPL.Functions.drop ds) (majorCells xs)

drop' :: MonadError Error m => Array -> Array -> m Array
drop' dro arr = do
  let err = DomainError "Drop left argument must be an integer vector"
  ds <- asVector err dro >>= mapM (asNumber err >=> asInt err)
  TinyAPL.Functions.drop ds arr

enclose :: MonadError Error m => Array -> m ScalarValue
enclose y = pure $ box y

enclose' :: MonadError Error m => Array -> m Array
enclose' = fmap scalar . enclose

halfPair :: MonadError Error m => Array -> m Array
halfPair y = pure $ vector [box y]

pair :: MonadError Error m => Array -> Array -> m Array
pair x y = pure $ vector $ box <$> [x, y]

first :: MonadError Error m => Array -> m Array
first (Array _ []) = throwError $ DomainError "First on empty array"
first (Array _ (x:_)) = pure $ fromScalar x

last :: MonadError Error m => Array -> m Array
last (Array _ []) = throwError $ DomainError "Last on empty array"
last (Array _ xs) = pure $ fromScalar $ Prelude.last xs

indexGenerator :: MonadError Error m => Natural -> m Array
indexGenerator 0 = pure $ vector []
indexGenerator i = pure $ vector $ Number . fromInteger . toInteger <$> [0..i - 1]

indexGeneratorN :: MonadError Error m => [Natural] -> m Array
indexGeneratorN is = pure $ fromJust $ arrayReshaped is $ box . fromJust . arrayReshaped [genericLength is] . fmap (Number . fromInteger . toInteger) <$> generateIndices is

indexGenerator' :: MonadError Error m => Array -> m Array
indexGenerator' arr = do
  let err = DomainError "Index Generator argument must be a natural scalar or vector"
  is <- asVector err arr >>= mapM (asNumber err >=> asNat err)
  if isScalar arr then indexGenerator $ headPromise is
  else indexGeneratorN is

range :: MonadError Error m => Array -> Array -> m Array
range = commute $ (indexGenerator' `atop` span') `leftFork` eachLeft add'

oneRange :: MonadError Error m => Array -> m Array
oneRange = range $ scalar $ Number 1

replicate :: MonadError Error m => [Natural] -> [a] -> m [a]
replicate [] [] = pure []
replicate (r:rs) (x:xs) = (genericReplicate r x ++) <$> TinyAPL.Functions.replicate rs xs
replicate _ _ = throwError $ LengthError "Replicate with different lengths"

replicate' :: MonadError Error m => Array -> Array -> m Array
replicate' rs arr = do
  let err = DomainError "Replicate left argument must be a natural vector or scalar"
  rs' <- asVector err rs >>= mapM (asNumber err >=> asNat err)
  let cells = majorCells arr
  rs'' <- if isScalar rs then case rs' of [r] -> pure $ Prelude.replicate (length cells) r; _ -> throwError unreachable else pure rs'
  fromMajorCells <$> TinyAPL.Functions.replicate rs'' cells

indices :: MonadError Error m => Array -> m Array
indices (Array sh cs) = do
  let err = DomainError "Indices argument must be an array of naturals"
  let indices = generateIndices sh
  let shape = [genericLength sh | length sh /= 1]
  let rep idx c = genericReplicate c $ box $ fromJust $ arrayReshaped shape $ Number . fromInteger . toInteger <$> idx
  counts <- mapM (asNumber err >=> asNat err) cs
  pure $ vector $ concat $ zipWith rep indices counts

unique :: (Eq a, MonadError Error m) => [a] -> m [a]
unique xs = pure $ nub xs

unique' :: MonadError Error m => Array -> m Array
unique' arr = fromMajorCells <$> unique (majorCells arr)

union :: (Eq a, MonadError Error m) => [a] -> [a] -> m [a]
union xs ys = pure $ xs ++ filter (Prelude.not . (`elem` xs)) ys

union' :: MonadError Error m => Array -> Array -> m Array
union' x y = fromMajorCells <$> union (majorCells x) (majorCells y)

intersection :: (Eq a, MonadError Error m) => [a] -> [a] -> m [a]
intersection xs ys = pure $ filter (`elem` ys) xs

intersection' :: MonadError Error m => Array -> Array -> m Array
intersection' x y = fromMajorCells <$> intersection (majorCells x) (majorCells y)

difference :: (Eq a, MonadError Error m) => [a] -> [a] -> m [a]
difference xs ys = pure $ filter (Prelude.not . (`elem` ys)) xs

difference' :: MonadError Error m => Array -> Array -> m Array
difference' x y = fromMajorCells <$> difference (majorCells x) (majorCells y)

symmetricDifference :: (Eq a, MonadError Error m) => [a] -> [a] -> m [a]
symmetricDifference xs ys = do
  a <- difference xs ys
  b <- difference ys xs
  pure $ a ++ b

symmetricDifference' :: MonadError Error m => Array -> Array -> m Array
symmetricDifference' x y = fromMajorCells <$> symmetricDifference (majorCells x) (majorCells y)

roll :: (MonadError Error m, MonadIO m) => Natural -> m Double
roll y =
  if y == 0 then randomR (0, 1)
  else fromInteger <$> randomR (0, toInteger y - 1)

roll' :: (MonadError Error m, MonadIO m) => Array -> m Array
roll' = scalarMonad $ \y -> do
  n <- asNumber expectedNatural y >>= asNat expectedNatural
  Number . (:+ 0) <$> roll n

indexCell :: MonadError Error m => Integer -> Array -> m Array
indexCell i x
  | i < 0 = indexCell (genericLength (majorCells x) + i) x
  | i > genericLength (majorCells x) = throwError $ DomainError "Index out of bounds"
  | otherwise = pure $ genericIndex (majorCells x) i

squad :: MonadError Error m => Array -> Array -> m Array
squad i y = do
  let err = DomainError "Squad left argument must be a vector of arrays of integers"
  axisIndices <- fmap fromScalar <$> asVector err i
  let
    go :: MonadError Error m => [Array] -> Array -> m Array
    go [] y = pure y
    go (is:iss) y =
      onScalars1 (\(Array [] [ind]) -> asNumber err ind >>= asInt err >>= flip indexCell y >>= go iss) is
  go axisIndices y

from :: MonadError Error m => Array -> Array -> m Array
from = (first `before` squad) `atRank2` (0, likePositiveInfinity)

catenate :: MonadError Error m => Array -> Array -> m Array
catenate a@(Array ash acs) b@(Array bsh bcs) =
  if arrayRank a == arrayRank b then
    if (isScalar a && isScalar b) || (tailMaybe ash == tailMaybe bsh) then pure $ fromMajorCells $ majorCells a ++ majorCells b
    else throwError $ LengthError "Incompatible shapes to Catenate"
  else if isScalar a then catenate (fromJust $ arrayReshaped (1 : tailPromise bsh) acs) b
  else if isScalar b then catenate a (fromJust $ arrayReshaped (1 : tailPromise ash) bcs)
  else if arrayRank a == arrayRank b + 1 then promote b >>= (a `catenate`)
  else if arrayRank a + 1 == arrayRank b then promote a >>= (`catenate` b)
  else throwError $ RankError "Incompatible ranks to Catenate"

gradeUp :: MonadError Error m => Ord a => [a] -> m [Natural]
gradeUp xs = pure $ map fst $ sortOn snd $ zip [0..genericLength xs] xs

gradeUp' :: MonadError Error m => Array -> m Array
gradeUp' arr = vector . fmap (Number . fromInteger . toInteger) <$> gradeUp (majorCells arr)

gradeDown :: MonadError Error m => Ord a => [a] -> m [Natural]
gradeDown xs = pure $ map fst $ sortOn snd $ zip [0..genericLength xs] (Down <$> xs)

gradeDown' :: MonadError Error m => Array -> m Array
gradeDown' arr = vector . fmap (Number . fromInteger . toInteger) <$> gradeDown (majorCells arr)

sortByUp :: MonadError Error m => Ord b => [a] -> [b] -> m [a]
sortByUp as bs = pure $ map fst $ sortOn snd $ zip as bs

sortByUp' :: MonadError Error m => Array -> Array -> m Array
sortByUp' as bs = fromMajorCells <$> sortByUp (majorCells as) (majorCells bs)

sortByDown :: MonadError Error m => Ord b => [a] -> [b] -> m [a]
sortByDown as bs = pure $ map fst $ sortOn snd $ zip as $ Down <$> bs

sortByDown' :: MonadError Error m => Array -> Array -> m Array
sortByDown' as bs = fromMajorCells <$> sortByDown (majorCells as) (majorCells bs)

sortUp :: MonadError Error m => Ord a =>[a] -> m [a]
sortUp = pure . sort

sortUp' :: MonadError Error m => Array -> m Array
sortUp' = fmap fromMajorCells . sortUp . majorCells

sortDown :: MonadError Error m => Ord a => [a] -> m [a]
sortDown = pure . fmap getDown . sort . fmap Down

sortDown' :: MonadError Error m => Array -> m Array
sortDown' = fmap fromMajorCells . sortDown . majorCells

reorderAxes' :: MonadError Error m => Array -> Array -> m Array
reorderAxes' x y = do
  shy <- shape' y
  sx <- sortUp' x
  is <- sortByUp' shy x
  is' <- key' ((reduce' min') `atop` (pure .: flip const)) sx is
  iota <- indexGenerator' is'
  indices <- eachRight from x iota
  from indices y

reorderAxes :: MonadError Error m => [Natural] -> Array -> m Array
reorderAxes is arr = reorderAxes' (vector $ Number . fromInteger . toInteger <$> is) arr

transpose :: MonadError Error m => Array -> m Array
transpose arr = do
  r <- rank' arr >>= indexGenerator' >>= reverse'
  reorderAxes' r arr

factorial :: MonadError Error m => ScalarValue -> m ScalarValue
factorial (Number n) = case asInt (DomainError "") n of
  Left _ -> pure $ Number $ Gamma.gamma $ n + 1
  Right i
    | i < 0 -> throwError $ DomainError "Factorial of a negative integer"
    | otherwise -> pure $ Number $ Gamma.factorial i
factorial _ = throwError expectedNumber

factorial' :: MonadError Error m => Array -> m Array
factorial' = scalarMonad factorial

binomial :: MonadError Error m => ScalarValue -> ScalarValue -> m ScalarValue
binomial (Number x) (Number y) = let
  go :: MonadError Error m => Complex Double -> Complex Double -> m (Complex Double)
  go n k = do
    let ni = asInt (DomainError "") n :: Either Error Integer
    let ki = asInt (DomainError "") k :: Either Error Integer
    case (ni, ki) of
      (Right n', Right k')
        | n' < 0 && k' >= 0 -> (((-1) ^ k') *) <$> go (k - n - 1) k
        | n' < 0 && k' <= n' -> (((-1) ^ (n' - k')) *) <$> go (-k - 1) (n - k)
        | n' < 0 -> pure 0
      (Right n', _) | n' < 0 -> throwError $ DomainError "If Choose left argument is a negative integer, the right argument must be an integer"
      (Right n', Right k')
        | k' < 0 || k' > n' -> pure 0
        | otherwise -> pure $ Gamma.factorial n' / (Gamma.factorial k' * Gamma.factorial (n' - k'))
      _ -> pure $ Gamma.gamma (n + 1) / (Gamma.gamma (k + 1) * Gamma.gamma (n - k + 1))
  in Number <$> go y x
binomial _ _ = throwError expectedNumber

binomial' :: MonadError Error m => Array -> Array -> m Array
binomial' = scalarDyad binomial

raise :: MonadError Error m => Int -> String -> m ()
raise = throwError .: fromErrorCode

raise' :: MonadError Error m => Array -> Array -> m Array
raise' code msg = do
  let err = DomainError "Raise left argument must be an integer scalar"
  code' <- asScalar err code >>= asNumber err >>= asInt err
  when (code' /= 0) $ raise code' $ show msg
  pure $ vector []

raise1 :: MonadError Error m => Array -> m Array
raise1 msg = do
  raise 1 $ show msg
  pure $ vector []

decode :: MonadError Error m => [Complex Double] -> [Complex Double] -> m (Complex Double)
decode ns cs =
  if length ns /= length cs then throwError $ LengthError "Decode arguments must have the same length"
  else pure $ sum $ zipWith (*) (Prelude.reverse $ scanl1 (*) (init $ 1 : Prelude.reverse ns)) cs

decode' :: MonadError Error m => Array -> Array -> m Array
decode' = (\ns cs -> do
  let err = DomainError "Decode arguments must be number arrays"
  cs' <- asVector err cs >>= mapM (asNumber err)
  ns' <- case asScalar err ns of
    Right x -> Prelude.replicate (length cs') <$> asNumber err x
    Left _ -> asVector err ns >>= mapM (asNumber err)
  scalar . Number <$> decode ns' cs') `atRank2` (1, 1)

decodeBase2 :: MonadError Error m => Array -> m Array
decodeBase2 = decode' (scalar $ Number 2)

encode :: MonadError Error m => [Complex Double] -> Complex Double -> m [Complex Double]
encode [] _ = pure []
encode (bs :> b) n = do
  let rem = if b == 0 then n else b `complexRemainder` n
  let div = if b == 0 then 0 else complexFloor $ n / b
  (`snoc` rem) <$> encode bs div

encodeScalar :: MonadError Error m => Complex Double -> Complex Double -> m [Complex Double]
encodeScalar b _ | Cx.magnitude b <= 1 = throwError $ DomainError "Scalar encode left argument must be greater than 1 in magnitude"
encodeScalar _ n | Number n == Number 0 = pure []
encodeScalar b n = do
  let rem = b `complexRemainder` n
  let div = complexFloor $ n / b
  let rem1 = b `complexRemainder` div
  let div1 = complexFloor $ div / b
  if rem == rem1 && div == div1 then pure [n]
  else (`snoc` rem) <$> encodeScalar b div

encode' :: MonadError Error m => Array -> Array -> m Array
encode' = (\b n -> do
  let err = DomainError "Encode arguments must be number arrays"
  n' <- asScalar err n >>= asNumber err
  case asScalar err b of
    Right b' -> vector . fmap Number . (\xs -> if null xs then [0] else xs) <$> (asNumber err b' >>= flip encodeScalar n')
    Left _ -> vector . fmap Number <$> (asVector err b >>= mapM (asNumber err) >>= flip encode n')) `atRank2` (1, 0)

encodeBase2 :: MonadError Error m => Array -> m Array
encodeBase2 = encode' (scalar $ Number 2)

searchFunction :: MonadError Error m => (Array -> [Array] -> m Array) -> Array -> Array -> m Array
searchFunction f ns hs = let cutRank = arrayRank hs `naturalSaturatedSub` 1
  in if arrayRank ns < cutRank then throwError $ DomainError "Search function neelde must have rank at least equal to the rank of the major cells of the haystack"
  else do
    let hc = majorCells hs
    nc <- atRank1 enclose' (toInteger cutRank) ns
    onScalars1 (\n -> do
      n' <- first n
      f n' hc) nc

elementOf :: MonadError Error m => Array -> Array -> m Array
elementOf = searchFunction $ pure .: scalar .: boolToScalar .: elem

count :: MonadError Error m => Array -> Array -> m Array
count = searchFunction $ pure .: scalar .: Number .: (:+ 0) .: countEqual

indexOf :: MonadError Error m => Array -> Array -> m Array
indexOf = flip $ searchFunction $ pure .: scalar .: Number .: (:+ 0) .: (\n hs -> fromMaybe (genericLength hs) $ n `genericElemIndex` hs)

intervalIndex :: MonadError Error m => Array -> Array -> m Array
intervalIndex hs' ns =
  if Prelude.not $ sorted $ majorCells hs' then throwError $ DomainError "Interval index left argument must be sorted"
  else (searchFunction $ pure .: scalar .: Number .: (:+ 0) .: (\n hs -> do
    let lowers = Nothing : fmap Just hs
    let uppers = fmap Just hs :> Nothing
    let bounds = Prelude.reverse $ zipWith3 (\l u i -> ((l, u), i)) lowers uppers [0..genericLength hs]
    fromMaybe 0 $ fmap snd $ flip find bounds $ \case
      ((Just lower, Just upper), _) | lower <= n && n < upper -> True
      ((Just lower, Nothing), _) | lower <= n -> True
      ((Nothing, Just upper), _) | n < upper -> True
      _ -> False)) ns hs'

laminate :: MonadError Error m => Array -> Array -> m Array
laminate = catenate `over` promote

majorCells' :: MonadError Error m => Array -> m Array
majorCells' = pure . vector . fmap box . majorCells

mix :: MonadError Error m => Array -> m Array
mix = atRank1 first 0

-- * Operators

compose :: MonadError Error m => (b -> m c) -> (a -> m b) -> a -> m c
compose f g = g >=> f

reverseCompose :: MonadError Error m => (a -> m b) -> (b -> m c) -> a -> m c
reverseCompose = flip compose

atop :: MonadError Error m => (c -> m d) -> (a -> b -> m c) -> a -> b -> m d
atop f g x y = g x y >>= f

over :: MonadError Error m => (b -> b -> m c) -> (a -> m b) -> a -> a -> m c
over f g x y = do
  x' <- g x
  y' <- g y
  f x' y'

after :: MonadError Error m => (a -> c -> m d) -> (b -> m c) -> a -> b -> m d
after f g x y = do
  y' <- g y
  f x y'

before :: MonadError Error m => (a -> m b) -> (b -> c -> m d) -> a -> c -> m d
before f g x y = do
  x' <- f x
  g x' y

leftHook :: MonadError Error m => (a -> m b) -> (b -> a -> m c) -> a -> m c
leftHook f g y = do
  y' <- f y
  g y' y

rightHook :: MonadError Error m => (a -> b -> m c) -> (a -> m b) -> a -> m c
rightHook f g y = do
  y' <- g y
  f y y'

fork1 :: MonadError Error m => (a -> m b) -> (b -> c -> m d) -> (a -> m c) -> a -> m d 
fork1 f g h x = do
  b <- h x
  a <- f x
  g a b

fork2 :: MonadError Error m => (a -> b -> m c) -> (c -> d -> m e) -> (a -> b -> m d) -> a -> b -> m e
fork2 f g h x y = do
  b <- h x y
  a <- f x y
  g a b

mirror :: MonadError Error m => (b -> b -> m c) -> (a -> a -> m b) -> a -> a -> m c
mirror f g x y = do
  b <- g x y
  a <- g y x
  f a b

leftFork :: MonadError Error m => (a -> b -> m c) -> (c -> b -> m d) -> a -> b -> m d
leftFork f g x y = do
  a <- f x y
  g a y

rightFork :: MonadError Error m => (a -> c -> m d) -> (a -> b -> m c) -> a -> b -> m d
rightFork f g x y = do
  a <- g x y
  f x a

constant1 :: MonadError Error m => a -> b -> m a
constant1 a _ = pure a

constant2 :: MonadError Error m => a -> b -> c -> m a
constant2 a _ _ = pure a

duplicate :: MonadError Error m => (a -> a -> m b) -> a -> m b
duplicate f y = f y y

commute :: MonadError Error m => (b -> a -> m c) -> a -> b -> m c
commute f x y = f y x

reduce :: MonadError Error m => (a -> a -> m a) -> [a] -> m a
reduce _ [] = throwError $ DomainError "Reduce empty axis"
reduce f (x:xs) = foldlM f x xs

reduce' :: MonadError Error m => (Array -> Array -> m Array) -> Array -> m Array
reduce' f = reduce f . majorCells

fold :: MonadError Error m => (a -> a -> m a) -> a -> [a] -> m a
fold = foldlM

fold' :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> m Array
fold' f s xs = fold f s $ majorCells xs

reduceBack :: MonadError Error m => (a -> a -> m a) -> [a] -> m a
reduceBack _ [] = throwError $ DomainError "Reduce empty axis"
reduceBack f (xs:>x) = foldrM f x xs

reduceBack' :: MonadError Error m => (Array -> Array -> m Array) -> Array -> m Array
reduceBack' f = reduceBack f . majorCells

foldBack :: MonadError Error m => (a -> a -> m a) -> a -> [a] -> m a
foldBack = foldrM

foldBack' :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> m Array
foldBack' f s xs = foldBack f s $ majorCells xs

onPrefixes :: MonadError Error m => ([a] -> m b) -> [a] -> m [b]
onPrefixes f = mapM f . prefixes

onPrefixes' :: MonadError Error m => (Array -> m Array) -> Array -> m Array
onPrefixes' f arr = fromMajorCells <$> onPrefixes (f . fromMajorCells) (majorCells arr)

onSuffixes :: MonadError Error m => ([a] -> m b) -> [a] -> m [b]
onSuffixes f = mapM f . suffixes

onSuffixes' :: MonadError Error m => (Array -> m Array) -> Array -> m Array
onSuffixes' f arr = fromMajorCells <$> onSuffixes (f . fromMajorCells) (majorCells arr)

each1 :: MonadError Error m => (Array -> m Array) -> Array -> m Array
each1 f (Array sh cs) = Array sh <$> mapM (fmap box . f . fromScalar) cs

each2 :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> m Array
each2 f (Array ash acs) (Array bsh bcs)
  | null ash && null bsh = scalar . box <$> f (fromScalar $ headPromise acs) (fromScalar $ headPromise bcs)
  | null ash = Array bsh <$> mapM (fmap box . ((fromScalar $ headPromise acs) `f`) . fromScalar) bcs
  | null bsh = Array ash <$> mapM (fmap box . (`f` (fromScalar $ headPromise bcs)) . fromScalar) acs
  | ash == bsh = Array ash <$> zipWithM (fmap box .: f) (fromScalar <$> acs) (fromScalar <$> bcs)
  | length ash /= length bsh = throwError $ RankError "Incompatible ranks to Each"
  | otherwise = throwError $ LengthError "Incompatible shapes to Each"

{-
We'd want to do this:

each1 :: MonadError Error m => (Array -> m Array) -> Array -> m Array
each1 = boxed1 . onContents1 . onScalars1

each2 :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> m Array
each2 = boxed2 . onContents2 . onScalars2

but atRank2 is defined using each2 (which I'm not sure I like), so we can't.
-}

boxed1 :: MonadError Error m => (Array -> m Array) -> Array -> m Array
boxed1 = compose enclose'

boxed2 :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> m Array
boxed2 = atop enclose'

onContents1 :: MonadError Error m => (Array -> m Array) -> Array -> m Array
onContents1 = (`compose` first)

onContents2 :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> m Array
onContents2 = (`over` first)

eachLeft :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> m Array
eachLeft f x y = each2 f x (scalar $ box y)

eachRight :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> m Array
eachRight f x = each2 f (scalar $ box x)

key :: (Eq a, MonadError Error m) => (a -> [b] -> m c) -> [a] -> [b] -> m [c]
key f ks vs
  | length ks == length vs = mapM (uncurry f) (group ks vs)
  | otherwise = throwError $ LengthError "Incompatible shapes to Key"

key' :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> m Array
key' f karr varr = fromMajorCells <$> key (\k vs -> f k $ vector $ toScalar <$> vs) (majorCells karr) (majorCells varr)

keyMonad :: MonadError Error m => (Array -> Array -> m Array) -> Array -> m Array
keyMonad f arr = do
  t <- tally' arr
  is <- indexGenerator' t
  key' f arr is

parseRank :: MonadError Error m => Array -> m (Integer, Integer, Integer)
parseRank arr = do
  let err = DomainError "Rank or depth right operand must be a 1-, 2- or 3-element integer vector"
  v <- asVector err arr >>= mapM (asNumber err >=> asInt err)
  case v of
    [d] -> pure (d, d, d)
    [d, e] -> pure (e, d, e)
    [d, e, f] -> pure (d, e, f)
    _ -> throwError err

atRank1 :: MonadError Error m => (Array -> m Array) -> Integer -> Array -> m Array
atRank1 f rank arr
  | arrayRank arr == 0 = f arr
  | rank >= 0 && toInteger (arrayRank arr) <= rank = f arr
  | rank >= 0 = fromMajorCells <$> mapM (atRank1 f rank) (majorCells arr)
  | rank == -1 = fromMajorCells <$> mapM f (majorCells arr)
  | otherwise = fromMajorCells <$> mapM (atRank1 f $ rank + 1) (majorCells arr)

atRank2 :: MonadError Error m => (Array -> Array -> m Array) -> (Integer, Integer) -> Array -> Array -> m Array
atRank2 f (ra, rb) a b = do
  -- @dzaima (in fact, {a b c←⌽3⍴⌽⍵⍵ ⋄ ↑(⊂⍤b⊢⍺) ⍺⍺¨ ⊂⍤c⊢⍵} is an impl of the dyadic case from the monadic one (with Dyalog's ↑ meaning))
  as <- atRank1 enclose' ra a
  bs <- atRank1 enclose' rb b
  each2 f as bs >>= atRank1 first 0

atRank1' :: MonadError Error m => (Array -> m Array) -> Array -> Array -> m Array
atRank1' f r y = do
  (a, _, _) <- parseRank r
  atRank1 f a y

atRank2' :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> Array -> m Array
atRank2' f r x y = do
  (_, b, c) <- parseRank r
  atRank2 f (b, c) x y

onCells1 :: MonadError Error m => (Array -> m Array) -> Array -> m Array
onCells1 f = atRank1 f (-1)

onCells2 :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> m Array
onCells2 f = atRank2 f (-1, -1)

onScalars1 :: MonadError Error m => (Array -> m Array) -> Array -> m Array
onScalars1 f = atRank1 f 0

onScalars2 :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> m Array
onScalars2 f = atRank2 f (0, 0)

atDepth1 :: MonadError Error m => (Array -> m Array) -> Integer -> Array -> m Array
atDepth1 f depth arr
  | arrayDepth arr == 0 || (depth >= 0 && toInteger (arrayDepth arr) <= depth) = f arr
  | depth == -1 = each1 f arr
  | otherwise = each1 (atDepth1 f $ depth + (if depth < 0 then 1 else 0)) arr

atDepth2 :: MonadError Error m => (Array -> Array -> m Array) -> (Integer, Integer) -> Array -> Array -> m Array
atDepth2 f (da, db) a b = go f (if da == 0 then likeNegativeInfinity else da, if db == 0 then likeNegativeInfinity else db) a b where
  go f (da, db) a b = let
    leftPure = da == 0 || arrayDepth a == 0 || (da >= 0 && toInteger (arrayDepth a) <= da)
    rightPure = db == 0 || arrayDepth b == 0 || (db >= 0 && toInteger (arrayDepth b) <= db)
    in case (leftPure, rightPure) of
      (True, True) -> f a b
      (True, False) -> atDepth1 (a `f`) db b
      (False, True) -> atDepth1 (`f` b) da a
      (False, False) -> each2 (go f (da + (if da < 0 then 1 else 0), db + (if db < 0 then 1 else 0))) a b

atDepth1' :: MonadError Error m => (Array -> m Array) -> Array -> Array -> m Array
atDepth1' f d y = do
  (a, _, _) <- parseRank d
  atDepth1 f a y

atDepth2' :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> Array -> m Array
atDepth2' f d x y = do
  (_, b, c) <- parseRank d
  atDepth2 f (b, c) x y

onSimpleScalars1 :: MonadError Error m => (Array -> m Array) -> Array -> m Array
onSimpleScalars1 f = atDepth1 f 0

onSimpleScalars2 :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> m Array
onSimpleScalars2 f = atDepth2 f (0, 0)

repeat :: MonadError Error m => (a -> m a) -> Natural -> a -> m a
repeat _ 0 x = pure x
repeat f n x = f x >>= TinyAPL.Functions.repeat f (n - 1)

until :: MonadError Error m => (a -> m a) -> (a -> a -> m Bool) -> a -> m a
until f p x = let
  go :: Monad m => (a -> m a) -> (a -> a -> m Bool) -> a -> a -> m a
  go f p prev x = do
    r <- f x
    t <- p r prev
    if t then pure r else go f p x r
  in f x >>= go f p x

repeat1 :: MonadError Error m => (Array -> m Array) -> Array -> Array -> m Array
repeat1 f t y = do
  let err = DomainError "Repeat right operand must be a natural scalar"
  n <- asScalar err t >>= asNumber err >>= asNat err
  TinyAPL.Functions.repeat f n y

repeat2 :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> Array -> m Array
repeat2 f t x y = do
  let err = DomainError "Repeat right operand must be a natural scalar"
  n <- asScalar err t >>= asNumber err >>= asNat err
  TinyAPL.Functions.repeat (f x) n y

until1 :: MonadError Error m => (Array -> m Array) -> (Array -> Array -> m Array) -> Array -> m Array
until1 f p y = let
  err = DomainError "Until right operand must return a boolean scalar"
  in TinyAPL.Functions.until f (\cu pr -> p cu pr >>= asScalar err >>= asBool err) y

until2 :: MonadError Error m => (Array -> Array -> m Array) -> (Array -> Array -> m Array) -> Array -> Array -> m Array
until2 f p x y = let
  err = DomainError "Until right operand must return a boolean scalar"
  in TinyAPL.Functions.until (f x) (\cu pr -> p cu pr >>= asScalar err >>= asBool err) y

under :: MonadError Error m => (Array -> m Array) -> (Array -> m Array) -> Array -> m Array
under f g arr = do
  let nums = fromJust $ arrayReshaped (arrayShape arr) $ Number . (:+ 0) <$> [1..]
  pairs <- atRank2 (atop enclose' pair) (0, 0) arr nums
  rs <- g pairs
  nums' <- atRank1 (compose TinyAPL.Functions.last first) 0 rs
  if Prelude.not $ distinct $ arrayContents rs then throwError $ DomainError "Under right operand must return each element at most once"
  else do
    res <- atRank1 (compose first first) 0 rs >>= f
    if isScalar res then do
      pure $ Array (arrayShape arr) $ zipWith (\num el -> if num `elem` (arrayContents nums') then headPromise $ arrayContents res else el) (arrayContents nums) (arrayContents arr)
    else if arrayShape nums' == arrayShape res then do
      let cs = zip (arrayContents nums') (arrayContents res)
      pure $ Array (arrayShape arr) $ zipWith (\num el -> case find (\(num', _) -> num == num') cs of
        Just (_, el') -> el'
        Nothing -> el) (arrayContents nums) (arrayContents arr)
    else throwError $ DomainError "Under left argument mustn't change the shape of the argument"

under2 :: MonadError Error m => (Array -> Array -> m Array) -> (Array -> m Array) -> Array -> Array -> m Array
under2 f g x = under (f x) g

underK :: MonadError Error m => Array -> (Array -> m Array) -> Array -> m Array
underK arr = under (\_ -> pure arr)

table :: MonadError Error m => (Array -> Array -> m Array) -> Array -> Array -> m Array
table f = atRank2 (atRank2 f (0, 0)) (0, likePositiveInfinity)

innerProduct :: MonadError Error m => (Array -> m Array) -> (Array -> Array -> m Array) -> Array -> Array -> m Array
innerProduct f g = atRank2 (atop f (atRank2 (atRank2 g (0, 0)) (-1, -1))) (1, likePositiveInfinity)
