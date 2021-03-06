-- | Open sound control 
{-# Language ScopedTypeVariables #-}
module Csound.Typed.Control.Osc(
    OscRef, OscHost, OscPort, OscAddress, OscType, 
    initOsc, listenOsc, sendOsc
) where

import Data.Boolean ((==*))

import Csound.Typed.Types
import Csound.Typed.GlobalState hiding (oscInit, oscListen, oscSend)
import qualified Csound.Typed.GlobalState as C(oscInit, oscListen, oscSend)

import Csound.Typed.Control.SERef


newtype OscRef = OscRef { unOscRef :: D }

-- | Port to listen OSC-messages.
type OscPort = Int

-- | Path-like string ("/foo/bar/baz")
type OscAddress = String

 
-- | The string specifies the type of expected arguments. 
-- The string can contain the characters "bcdfilmst" which stand for 
-- Boolean, character, double, float, 32-bit integer, 64-bit integer, MIDI, 
-- string and timestamp.
type OscType = String

-- | The hostname of the computer. An empty string is for local machine.
type OscHost = String

-- | Initializes host client. The process starts to run in the background.
initOsc :: OscPort -> SE OscRef
initOsc port = do
    oscRef <- fmap fromGE $ fromDep $ C.oscInit (fromIntegral port)
    varRef <- newGlobalSERef (0 :: D)
    writeSERef varRef oscRef
    ihandle <- readSERef varRef
    return $ OscRef ihandle

-- | Listens for the OSC-messages. The first argument is OSC-reference.
-- We can create it with the function @oscInit@. The next two arguments are strings.
-- The former specifies the path-like address to listen the messages. It can be:
--
-- > /foo/bar/baz
--
-- The latter specifies the type of expected arguments. 
-- The string can contain the characters "bcdfilmst" which stand for 
-- Boolean, character, double, float, 32-bit integer, 64-bit integer, MIDI, 
-- string and timestamp.
--
-- The result is an event of messages. We can run a callback on it
-- with standard function @runEvt@:
--
-- > runEvt :: Evt a -> (a -> SE ()) -> SE ()
listenOsc :: forall a . Tuple a => OscRef -> OscAddress -> OscType -> Evt a
listenOsc oscRef oscAddr oscType = Evt $ \bam -> do
    (readCond, writeCond) <- sensorsSE (0 :: Sig)
    resRef <- newSERef (defTuple :: a)
    writeCond =<< listen resRef
    readCond >>= (\cond -> whileDo (cond ==* 1) $ do
        bam =<< readSERef resRef
        writeCond =<< listen resRef)
    where
        listen :: Tuple a => SERef a -> SE Sig
        listen ref = csdOscListen ref oscRef oscAddr oscType

        csdOscListen :: Tuple a => SERef a -> OscRef -> OscAddress -> OscType -> SE Sig
        csdOscListen resRef oscHandle addr ty = do
            args <- readSERef resRef
            res  <- fmap fromGE $ fromDep $ hideGEinDep $ do 
                expArgs <- fromTuple args
                expOscHandle <- toGE $ unOscRef oscHandle
                expAddr <- toGE $ text addr
                expOscType <- toGE $ text ty
                return $ C.oscListen $ expOscHandle : expAddr : expOscType : expArgs
            writeSERef resRef args
            return res

-- | Sends OSC-messages. It takes in a name of the host computer 
-- (empty string is alocal machine), port on which the target 
-- machine is listening, OSC-addres and type. The last argument
-- produces the values for OSC-messages.
sendOsc :: forall a . Tuple a => OscHost -> OscPort -> OscAddress -> OscType -> Evt a -> SE ()
sendOsc host port addr ty evts = runEvt evts send
    where 
        send :: Tuple a => a -> SE ()
        send as = SE $ hideGEinDep $ do
            args <- fromTuple as
            expHost <- toGE $ text $ host
            expPort <- toGE $ int  $ port
            expAddr <- toGE $ text $ addr
            expTy   <- toGE $ text $ ty
            return $ C.oscSend $ 1 : expHost : expPort : expAddr : expTy : args

