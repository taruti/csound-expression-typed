{-# Language TypeFamilies, FlexibleInstances, FlexibleContexts, ScopedTypeVariables, Rank2Types #-}
module Csound.Typed.Types.Prim(
    Sig(..), unSig, D(..), unD, Tab(..), unTab, Str(..), Spec(..), Wspec(..), 
    BoolSig(..), unBoolSig, BoolD(..), unBoolD, Unit(..), unit, Val(..), hideGE, SigOrD,

    -- ** Tables
    preTab, TabSize(..), TabArgs(..), updateTabSize,
    fromPreTab, getPreTabUnsafe, skipNorm, forceNorm,
    nsamp, ftlen, ftchnls, ftsr, ftcps,

    -- ** constructors
    double, int, text, 
    
    -- ** constants
    idur, getSampleRate, getControlRate, getBlockSize, getZeroDbfs,

    -- ** converters
    ar, kr, ir, sig,

    -- ** lifters
    on0, on1, on2, on3,

    -- ** numeric funs
    quot', rem', div', mod', ceil', floor', round', int', frac',
   
    -- ** logic funs
    when1, whens, untilDo, whileDo, boolSig
) where

import Prelude hiding((<*))

import Control.Applicative hiding ((<*))
import Control.Monad
import Control.Monad.Trans.Class
import Data.Monoid
import qualified Data.IntMap as IM

import Data.Default
import Data.Boolean

import Csound.Dynamic hiding (double, int, str, when1, whens, ifBegin, ifEnd, elseBegin, untilBegin, untilEnd, untilDo)
import qualified Csound.Dynamic as D(double, int, str, ifBegin, ifEnd, elseBegin, untilBegin, untilEnd)
import Csound.Typed.GlobalState.GE
import Csound.Typed.GlobalState.SE
import Csound.Typed.GlobalState.Options

-- | Signals
data Sig  
    = Sig  (GE E)
    | PrimSig Double

unSig :: Sig -> GE E
unSig = toGE

-- | Constant numbers
data D    
    = D  (GE E)
    | PrimD Double

unD :: D -> GE E
unD = toGE

-- | Strings
newtype Str  = Str  { unStr :: GE E }

-- | Spectrum. It's @fsig@ in the Csound.
newtype Spec  = Spec  { unSpec  :: GE E }

-- | Another type for spectrum. It's @wsig@ in the Csound.
newtype Wspec = Wspec { unWspec :: GE E }

-- Booleans

-- | A signal of booleans.
data BoolSig 
    = BoolSig (GE E)
    | PrimBoolSig Bool

unBoolSig :: BoolSig -> GE E
unBoolSig = toGE

-- | A constant boolean value.
data BoolD   
    = BoolD (GE E)
    | PrimBoolD Bool

unBoolD :: BoolD -> GE E
unBoolD = toGE

type instance BooleanOf Sig  = BoolSig

type instance BooleanOf D    = BoolD
type instance BooleanOf Str  = BoolD
type instance BooleanOf Tab  = BoolD
type instance BooleanOf Spec = BoolD

-- Procedures

-- | Csound's empty tuple.
newtype Unit = Unit { unUnit :: GE () } 

-- | Constructs Csound's empty tuple.
unit :: Unit
unit = Unit $ return ()

instance Monoid Unit where
    mempty = Unit (return ())
    mappend a b = Unit $ (unUnit a) >> (unUnit b)

instance Default Unit where
    def = unit

-- tables

-- | Tables (or arrays)
data Tab  
    = Tab (GE E)
    | TabPre PreTab

preTab :: TabSize -> Int -> TabArgs -> Tab
preTab size gen args = TabPre $ PreTab size gen args

data PreTab = PreTab
    { preTabSize    :: TabSize
    , preTabGen     :: Int
    , preTabArgs    :: TabArgs }

-- Table size.
data TabSize 
    -- Size is fixed by the user.
    = SizePlain Int
    -- Size is relative to the renderer settings.
    | SizeDegree 
    { hasGuardPoint :: Bool
    , sizeDegree    :: Int      -- is the power of two
    }

instance Default TabSize where
    def = SizeDegree
        { hasGuardPoint = False
        , sizeDegree = 0 }
    
-- Table arguments can be
data TabArgs 
    -- absolute
    = ArgsPlain [Double]
    -- or relative to the table size (used for tables that implement interpolation)
    | ArgsRelative [Double]
    -- GEN 16 uses unusual interpolation scheme, so we need a special case
    | ArgsGen16 [Double]
    | FileAccess String [Double]

renderTab :: PreTab -> GE E
renderTab a = saveGen =<< fromPreTab a 

getPreTabUnsafe :: String -> Tab -> PreTab
getPreTabUnsafe msg x = case x of
    TabPre a    -> a
    _           -> error msg

fromPreTab :: PreTab -> GE Gen
fromPreTab a = withOptions $ \opt -> go (defTabFi opt) a
    where
        go :: TabFi -> PreTab -> Gen
        go tabFi tab = Gen size (preTabGen tab) args file
            where size = defineTabSize (getTabSizeBase tabFi tab) (preTabSize tab)
                  (args, file) = defineTabArgs size (preTabArgs tab)

getTabSizeBase :: TabFi -> PreTab -> Int
getTabSizeBase tf tab = IM.findWithDefault (tabFiBase tf) (preTabGen tab) (tabFiGens tf)

defineTabSize :: Int -> TabSize -> Int
defineTabSize base x = case x of
       SizePlain n -> n
       SizeDegree guardPoint degree ->          
                byGuardPoint guardPoint $
                byDegree base degree
    where byGuardPoint guardPoint 
            | guardPoint = (+ 1)
            | otherwise  = id
            
          byDegree zero n = 2 ^ max 0 (zero + n) 

defineTabArgs :: Int -> TabArgs -> ([Double], Maybe String)
defineTabArgs size args = case args of
    ArgsPlain as -> (as, Nothing)
    ArgsRelative as -> (fromRelative size as, Nothing)
    ArgsGen16 as -> (formRelativeGen16 size as, Nothing)
    FileAccess filename as -> (as, Just filename)
    where fromRelative n as = substEvens (mkRelative n $ getEvens as) as
          getEvens xs = case xs of
            [] -> []
            _:[] -> []
            _:b:as -> b : getEvens as
            
          substEvens evens xs = case (evens, xs) of
            ([], as) -> as
            (_, []) -> []
            (e:es, a:_:as) -> a : e : substEvens es as
            _ -> error "table argument list should contain even number of elements"
            
          mkRelative n as = fmap ((fromIntegral :: (Int -> Double)) . round . (s * )) as
            where s = fromIntegral n / sum as
          
          -- special case. subst relatives for Gen16
          formRelativeGen16 n as = substGen16 (mkRelative n $ getGen16 as) as

          getGen16 xs = case xs of
            _:durN:_:rest    -> durN : getGen16 rest
            _                -> []

          substGen16 durs xs = case (durs, xs) of 
            ([], as) -> as
            (_, [])  -> []
            (d:ds, valN:_:typeN:rest)   -> valN : d : typeN : substGen16 ds rest
            (_, _)   -> xs

-- | Skips normalization (sets table size to negative value)
skipNorm :: Tab -> Tab
skipNorm x = case x of
    Tab _ -> error "you can skip normalization only for primitive tables (made with gen-routines)"
    TabPre a -> TabPre $ a{ preTabGen = negate $ abs $ preTabGen a }

-- | Force normalization (sets table size to positive value).
-- Might be useful to restore normalization for table 'Csound.Tab.doubles'.
forceNorm :: Tab -> Tab
forceNorm x = case x of
    Tab _ -> error "you can force normalization only for primitive tables (made with gen-routines)"
    TabPre a -> TabPre $ a{ preTabGen = abs $ preTabGen a }

----------------------------------------------------------------------------
-- change table size

updateTabSize :: (TabSize -> TabSize) -> Tab -> Tab
updateTabSize phi x = case x of
    Tab _ -> error "you can change size only for primitive tables (made with gen-routines)"
    TabPre a -> TabPre $ a{ preTabSize = phi $ preTabSize a }

-------------------------------------------------------------------------------
-- constructors

-- | Constructs a number.
double :: Double -> D
double = PrimD

-- | Constructs an integer.
int :: Int -> D
int =  PrimD . fromIntegral

-- | Constructs a string.
text :: String -> Str
text = fromE . D.str

-------------------------------------------------------------------------------
-- constants

-- | Querries a total duration of the note. It's equivallent to Csound's @p3@ field.
idur :: D 
idur = fromE $ pn 3

getSampleRate :: D
getSampleRate = fromE $ readOnlyVar (VarVerbatim Ir "sr")

getControlRate :: D
getControlRate = fromE $ readOnlyVar (VarVerbatim Ir "kr")

getBlockSize :: D
getBlockSize = fromE $ readOnlyVar (VarVerbatim Ir "ksmps")

getZeroDbfs :: D
getZeroDbfs = fromE $ readOnlyVar (VarVerbatim Ir "0dbfs")

-------------------------------------------------------------------------------
-- converters

-- | Sets a rate of the signal to audio rate.
ar :: Sig -> Sig
ar = on1 $ setRate Ar

-- | Sets a rate of the signal to control rate.
kr :: Sig -> Sig
kr = on1 $ setRate Kr

-- | Converts a signal to the number (initial value of the signal).
ir :: Sig -> D
ir = on1 $ setRate Ir

-- | Makes a constant signal from the number.
sig :: D -> Sig
sig = on1 $ setRate Kr

-------------------------------------------------------------------------------
-- single wrapper

-- | Contains all Csound values.
class Val a where
    fromGE  :: GE E -> a
    toGE    :: a -> GE E

    fromE   :: E -> a
    fromE = fromGE . return

hideGE :: Val a => GE a -> a
hideGE = fromGE . join . fmap toGE

instance Val Sig    where 
    fromGE = Sig    
    
    toGE x = case x of
        Sig a       -> a
        PrimSig d   -> return $ D.double d

instance Val D      where 
    fromGE  = D
    toGE x  = case x of
        D a     -> a
        PrimD d -> return $ D.double d

instance Val Str    where { fromGE = Str    ; toGE = unStr  }
instance Val Spec   where { fromGE = Spec   ; toGE = unSpec }
instance Val Wspec  where { fromGE = Wspec  ; toGE = unWspec}

instance Val Tab where 
    fromGE = Tab 
    toGE = unTab

unTab :: Tab -> GE E
unTab x = case x of
        Tab a -> a
        TabPre a -> renderTab a

instance Val BoolSig where 
    fromGE = BoolSig 
    toGE x = case x of
        BoolSig a -> a
        PrimBoolSig b -> return $ if b then 1 else 0

instance Val BoolD   where 
    fromGE = BoolD
    toGE x = case x of
        BoolD a -> a
        PrimBoolD b -> return $ if b then 1 else 0   


class (IsPrim a, RealFrac (PrimOf a), Val a) => SigOrD a where

instance SigOrD Sig where
instance SigOrD D   where

on0 :: Val a => E -> a
on0 = fromE

on1 :: (Val a, Val b) => (E -> E) -> (a -> b)
on1 f a = fromGE $ fmap f $ toGE a

on2 :: (Val a, Val b, Val c) => (E -> E -> E) -> (a -> b -> c)
on2 f a b = fromGE $ liftA2 f (toGE a) (toGE b)

on3 :: (Val a, Val b, Val c, Val d) => (E -> E -> E -> E) -> (a -> b -> c -> d)
on3 f a b c = fromGE $ liftA3 f (toGE a) (toGE b) (toGE c)

op1 :: (Val a, Val b, IsPrim a, IsPrim b) => (PrimOf a -> PrimOf b) -> (E -> E) -> (a -> b)
op1 primFun exprFun x = maybe (on1 exprFun x) (fromPrim . primFun) (getPrim x)

op2 :: (Val a, Val b, Val c, IsPrim a, IsPrim b, IsPrim c) => (PrimOf a -> PrimOf b -> PrimOf c) -> (E -> E -> E) -> (a -> b -> c)
op2 primFun exprFun xa xb = case (getPrim xa, getPrim xb) of
    (Just a, Just b) -> fromPrim $ primFun a b
    _                -> on2 exprFun xa xb

-------------------------------------------------------------------------------
-- defaults

instance Default Sig    where def = 0
instance Default D      where def = 0
instance Default Tab    where def = fromE 0
instance Default Str    where def = text ""
instance Default Spec   where def = fromE 0 

-------------------------------------------------------------------------------
-- monoid

instance Monoid Sig     where { mempty = on0 mempty     ; mappend = on2 mappend }
instance Monoid D       where { mempty = on0 mempty     ; mappend = on2 mappend }

-------------------------------------------------------------------------------
-- numeric

sigOn1 :: (Double -> Double) -> (E -> E) -> (Sig -> Sig)
sigOn1 numFun exprFun x = case x of
    PrimSig a -> PrimSig $ numFun a
    _         -> on1 exprFun x

sigOn2 :: (Double -> Double -> Double) -> (E -> E -> E) -> (Sig -> Sig -> Sig)
sigOn2 numFun exprFun xa xb = case (xa, xb) of
    (PrimSig a, PrimSig b) -> PrimSig $ numFun a b
    _                      -> on2 exprFun xa xb


instance Num Sig where 
    { (+) = sigOn2 (+) (+); (*) = sigOn2 (*) (*); negate = sigOn1 negate negate
    ; (-) = sigOn2 (\a b -> a - b) (\a b -> a - b)
    ; fromInteger = PrimSig . fromInteger; abs = sigOn1 abs abs; signum = sigOn1 signum signum }

dOn1 :: (Double -> Double) -> (E -> E) -> (D -> D)
dOn1 numFun exprFun x = case x of
    PrimD a -> PrimD $ numFun a
    _         -> on1 exprFun x

dOn2 :: (Double -> Double -> Double) -> (E -> E -> E) -> (D -> D -> D)
dOn2 numFun exprFun xa xb = case (xa, xb) of
    (PrimD a, PrimD b) -> PrimD $ numFun a b
    _                      -> on2 exprFun xa xb

instance Num D where 
    { (+) = dOn2 (+) (+); (*) = dOn2 (*) (*); negate = dOn1 negate negate
    ; (-) = dOn2 (\a b -> a - b) (\a b -> a - b)
    ; fromInteger = PrimD . fromInteger; abs = dOn1 abs abs; signum = dOn1 signum signum }

instance Fractional Sig  where { (/) = sigOn2 (/) (/);  fromRational = PrimSig . fromRational }
instance Fractional D    where { (/) = dOn2 (/) (/);    fromRational = PrimD . fromRational }

instance Floating Sig where
    { pi = PrimSig pi;  exp = sigOn1 exp exp;  sqrt = sigOn1 sqrt sqrt; log = sigOn1 log log; logBase = sigOn2 logBase logBase; (**) = sigOn2 (**) (**)
    ; sin = sigOn1 sin sin;  tan = sigOn1 tan tan;  cos = sigOn1 cos cos; sinh = sigOn1 sinh sinh; tanh = sigOn1 tanh tanh; cosh = sigOn1 cosh cosh
    ; asin = sigOn1 asin asin; atan = sigOn1 atan atan;  acos = sigOn1 acos acos ; asinh = sigOn1 asinh asinh; acosh = sigOn1 acosh acosh; atanh = sigOn1 atanh atanh }

instance Floating D where
    { pi = PrimD pi;  exp = dOn1 exp exp;  sqrt = dOn1 sqrt sqrt; log = dOn1 log log;  logBase = dOn2 logBase logBase; (**) = dOn2 (**) (**)
    ; sin = dOn1 sin sin;  tan = dOn1 tan tan;  cos = dOn1 cos cos; sinh = dOn1 sinh sinh; tanh = dOn1 tanh tanh; cosh = dOn1 cosh cosh
    ; asin = dOn1 asin asin; atan = dOn1 atan atan;  acos = dOn1 acos acos ; asinh = dOn1 asinh asinh; acosh = dOn1 acosh acosh; atanh = dOn1 atanh atanh }

class IsPrim a where
    type PrimOf a :: *
    getPrim :: a -> Maybe (PrimOf a)
    fromPrim :: PrimOf a -> a

instance IsPrim Sig where
    type PrimOf Sig = Double
    
    getPrim x = case x of
        PrimSig a -> Just a
        _         -> Nothing

    fromPrim = PrimSig

instance IsPrim D where
    type PrimOf D = Double
    
    getPrim x = case x of
        PrimD a -> Just a
        _         -> Nothing

    fromPrim = PrimD

instance IsPrim BoolSig where
    type PrimOf BoolSig = Bool
    
    getPrim x = case x of
        PrimBoolSig a -> Just a
        _         -> Nothing

    fromPrim = PrimBoolSig

instance IsPrim BoolD where
    type PrimOf BoolD = Bool
    
    getPrim x = case x of
        PrimBoolD a -> Just a
        _         -> Nothing

    fromPrim = PrimBoolD


ceil', floor', int', round' :: SigOrD a => a -> a
quot', rem', div', mod' :: SigOrD a => a -> a -> a

frac' :: (SigOrD a) => a -> a
frac' a = op1 (\x -> proxySnd a (properFraction x)) fracE a
    where
        proxySnd :: SigOrD a => a -> (Int, PrimOf a) -> PrimOf a
        proxySnd _ x = snd x

ceil' = op1 (\x -> fromIntegral ((ceiling x) :: Int)) ceilE
floor' = op1 (\x -> fromIntegral ((floor x) :: Int)) floorE
int' = op1 (\x -> fromIntegral ((truncate x) :: Int)) intE
round' = op1 (\x -> fromIntegral ((round x) :: Int)) roundE
quot' = op2 (\a b -> fromIntegral $ quot ((truncate a) :: Int) ((truncate b):: Int)) quot
rem' = op2 (\a b -> fromIntegral $ rem ((truncate a) :: Int) ((truncate b):: Int)) rem  
div' = op2 (\a b -> fromIntegral $ div ((truncate a) :: Int) ((truncate b):: Int)) div   
mod' = op2 (\a b -> fromIntegral $ mod ((truncate a) :: Int) ((truncate b):: Int)) mod

-------------------------------------------------------------------------------
-- logic

boolSigOn1 :: (Bool -> Bool) -> (E -> E) -> BoolSig -> BoolSig
boolSigOn1 = op1

boolSigOn2 :: (Bool -> Bool -> Bool) -> (E -> E -> E) -> BoolSig -> BoolSig -> BoolSig
boolSigOn2 = op2 

boolDOn1 :: (Bool -> Bool) -> (E -> E) -> BoolD -> BoolD
boolDOn1 = op1

boolDOn2 :: (Bool -> Bool -> Bool) -> (E -> E -> E) -> BoolD -> BoolD -> BoolD
boolDOn2 = op2 

instance Boolean BoolSig  where { true = PrimBoolSig True;  false = PrimBoolSig False;  notB = boolSigOn1 not notB;  (&&*) = boolSigOn2 (&&) (&&*);  (||*) = boolSigOn2 (||) (||*) }
instance Boolean BoolD    where { true = PrimBoolD   True;  false = PrimBoolD   False;  notB = boolDOn1   not notB;  (&&*) = boolDOn2   (&&) (&&*);  (||*) = boolDOn2   (||) (||*) }

instance IfB Sig  where 
    ifB x a b = case x of
        PrimBoolSig cond -> if cond then a else b
        _                -> on3 ifB x a b

instance IfB D    where 
    ifB x a b = case x of
        PrimBoolD cond -> if cond then a else b
        _              -> on3 ifB x a b

instance IfB Tab  where 
    ifB x a b = case x of
        PrimBoolD cond -> if cond then a else b
        _              -> on3 ifB x a b

instance IfB Str  where 
    ifB x a b = case x of
        PrimBoolD cond -> if cond then a else b
        _              -> on3 ifB x a b

instance IfB Spec where 
    ifB x a b = case x of
        PrimBoolD cond -> if cond then a else b
        _              -> on3 ifB x a b

instance EqB Sig  where { (==*) = op2 (==) (==*);    (/=*) = op2 (/=) (/=*) }
instance EqB D    where { (==*) = op2 (==) (==*);    (/=*) = op2 (/=) (/=*) }

instance OrdB Sig where { (<*)  = op2 (<) (<*) ;    (>*)  = op2 (>) (>*);     (<=*) = op2 (<=) (<=*);    (>=*) = op2 (>=) (>=*) }
instance OrdB D   where { (<*)  = op2 (<) (<*) ;    (>*)  = op2 (>) (>*);     (<=*) = op2 (<=) (<=*);    (>=*) = op2 (>=) (>=*) }

-- | Invokes the given procedure if the boolean signal is true.
when1 :: BoolSig -> SE () -> SE ()
when1 xp body = case xp of
    PrimBoolSig p -> if p then body else return ()
    _             -> do
        ifBegin xp
        body
        ifEnd

-- | The chain of @when1@s. Tests all the conditions in sequence
-- if everything is false it invokes the procedure given in the second argument.
whens :: [(BoolSig, SE ())] -> SE () -> SE ()
whens bodies el = case bodies of
    []   -> el
    a:as -> do
        ifBegin (fst a)
        snd a
        elseIfs as
        elseBegin 
        el
        foldl1 (>>) $ replicate (length bodies) ifEnd
    where elseIfs = mapM_ (\(p, body) -> elseBegin >> ifBegin p >> body)

ifBegin :: BoolSig -> SE ()
ifBegin a = fromDep_ $ D.ifBegin =<< lift (toGE a)

ifEnd :: SE ()
ifEnd = fromDep_ D.ifEnd

elseBegin :: SE ()
elseBegin = fromDep_ D.elseBegin

-- elseIfBegin :: BoolSig -> SE ()
-- elseIfBegin a = fromDep_ $ D.elseIfBegin =<< lift (toGE a)

untilDo :: BoolSig -> SE () -> SE ()
untilDo p body = do
    untilBegin p
    body
    untilEnd

whileDo :: BoolSig -> SE () -> SE ()
whileDo p = untilDo (notB p) 

untilBegin :: BoolSig -> SE ()
untilBegin a = fromDep_ $ D.untilBegin =<< lift (toGE a)

untilEnd :: SE ()
untilEnd = fromDep_ D.untilEnd

-- | Creates a constant boolean signal.
boolSig :: BoolD -> BoolSig
boolSig x = case x of
    PrimBoolD b -> PrimBoolSig b
    BoolD a     -> BoolSig a

----------------------------------------------

-- | nsamp — Returns the number of samples loaded into a stored function table number.
--
-- > nsamp(x) (init-rate args only)
--
-- csound doc: <http://www.csounds.com/manual/html/nsamp.html>
nsamp :: Tab -> D
nsamp = on1 $ opr1 "nsamp"

-- | Returns a length of the table.
ftlen :: Tab -> D
ftlen = on1 $ opr1 "ftlen"

-- | Returns the number of channels for a table that stores wav files
ftchnls :: Tab -> D
ftchnls = on1 $ opr1 "ftchnls"

-- | Returns the sample rate for a table that stores wav files
ftsr :: Tab -> D
ftsr = on1 $ opr1 "ftsr"

-- | Returns the base frequency for a table that stores wav files
ftcps :: Tab -> D
ftcps = on1 $ opr1 "ftcps"

