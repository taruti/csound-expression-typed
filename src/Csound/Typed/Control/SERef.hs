module Csound.Typed.Control.SERef where

import Control.DeepSeq(deepseq)

import Control.Monad
import Csound.Dynamic hiding (newLocalVars)

import Csound.Typed.Types.Tuple
import Csound.Typed.GlobalState.SE

-- | It describes a reference to mutable values.
newtype SERef a = SERef [Var]
{-
    { writeSERef :: a -> SE ()
    , readSERef  :: SE a }
-}

writeSERef :: Tuple a => SERef a -> a -> SE ()
writeSERef (SERef vars) a = fromDep_ $ hideGEinDep $ do
    vals <- fromTuple a
    return $ zipWithM_ writeVar vars vals

--    (zipWithM_ writeVar vars) =<< lift (fromTuple a)
--writeVar :: Var -> E -> Dep ()
--[Var] (GE [E])

readSERef  :: Tuple a => SERef a -> SE a
readSERef (SERef vars) = SE $ fmap (toTuple . return) $ mapM readVar vars

-- | Allocates a new local (it is visible within the instrument) mutable value and initializes it with value. 
-- A reference can contain a tuple of variables.
newSERef :: Tuple a => a -> SE (SERef a)
newSERef t = fmap SERef $ newLocalVars (tupleRates t) (fromTuple t)    
   
-- | Adds the given signal to the value that is contained in the
-- reference.
mixSERef :: (Num a, Tuple a) => SERef a -> a -> SE ()
mixSERef ref asig = modifySERef ref (+ asig)

-- | Modifies the SERef value with given function.
modifySERef :: Tuple a => SERef a -> (a -> a) -> SE ()
modifySERef ref f = do
    v <- readSERef ref      
    writeSERef ref (f v)

-- | An alias for the function @newSERef@. It returns not the reference
-- to mutable value but a pair of reader and writer functions.
sensorsSE :: Tuple a => a -> SE (SE a, a -> SE ())
sensorsSE a = do
    ref <- newSERef a
    return $ (readSERef ref, writeSERef ref)

-- | Allocates a new global mutable value and initializes it with value. 
-- A reference can contain a tuple of variables.
newGlobalSERef :: Tuple a => a -> SE (SERef a)
newGlobalSERef t = fmap SERef $ newGlobalVars (tupleRates t) (fromTuple t)    

-- | An alias for the function @newSERef@. It returns not the reference
-- to mutable value but a pair of reader and writer functions.
globalSensorsSE :: Tuple a => a -> SE (SE a, a -> SE ())
globalSensorsSE a = do
    ref <- newSERef a
    return $ (readSERef ref, writeSERef ref)
