module Csound.Typed.GlobalState.SE(
    SE(..), LocalHistory(..), 
    runSE, execSE, evalSE, execGEinSE, hideGEinDep, 
    fromDep, fromDep_, 
    newLocalVar, newLocalVars        
) where

import Control.Applicative
import Control.Monad
import Control.Monad.Trans.Class

import Csound.Dynamic hiding (newLocalVar, newLocalVars)
import qualified Csound.Dynamic as D(newLocalVar, newLocalVars)
import Csound.Typed.GlobalState.GE

-- | The Csound's @IO@-monad. All values that produce side effects are wrapped
-- in the @SE@-monad.
newtype SE a = SE { unSE :: Dep a }

instance Functor SE where
    fmap f = SE . fmap f . unSE

instance Applicative SE where
    pure = return
    (<*>) = ap

instance Monad SE where
    return = SE . return
    ma >>= mf = SE $ unSE ma >>= unSE . mf

runSE :: SE a -> GE (a, LocalHistory)
runSE = runDepT . unSE

execSE :: SE a -> Dep () 
execSE = depT_ . execDepT . unSE 

execGEinSE :: SE (GE a) -> SE a
execGEinSE (SE sa) = SE $ do
    ga <- sa
    a  <- lift ga
    return a

hideGEinDep :: GE (Dep a) -> Dep a
hideGEinDep = join . lift

fromDep :: Dep a -> SE (GE a)
fromDep = fmap return . SE 

fromDep_ :: Dep () -> SE ()
fromDep_ = SE
            
evalSE :: SE a -> GE a
evalSE = fmap fst . runSE

----------------------------------------------------------------------
-- allocation of the local vars

newLocalVars :: [Rate] -> GE [E] -> SE [Var]
newLocalVars rs vs = SE $ D.newLocalVars rs vs

newLocalVar :: Rate -> GE E -> SE Var
newLocalVar rate val = SE $ D.newLocalVar rate val

