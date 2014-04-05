{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE RankNTypes #-}

-- | Turn a 'Get' into a 'Sink' and a 'Put' into a 'Source'
-- These functions are built upno the Data.Conduit.Cereal.Internal functions with default
-- implementations of 'ErrorHandler' and 'TerminationHandler'
--
-- The default 'ErrorHandler' and 'TerminationHandler' both throw a 'GetException'.

module Data.Conduit.Cereal ( GetException
                           , sinkGet
                           , conduitGet
                           , sourcePut
                           , conduitPut
                           ) where

import           Conduit
import           Control.Exception.Base
import           Control.Monad.Trans.Class (MonadTrans, lift)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import           Data.Serialize hiding (get, put)
import           Data.Typeable

import           Data.Conduit.Cereal.Internal

data GetException = GetException String
  deriving (Show, Typeable)

instance Exception GetException

-- | Run a 'Get' repeatedly on the input stream, producing an output stream of whatever the 'Get' outputs.
conduitGet :: MonadThrow m => Get o -> Conduit BS.ByteString m o
conduitGet = mkConduitGet errorHandler
  where errorHandler msg = pipeError $ GetException msg

-- | Convert a 'Get' into a 'Sink'. The 'Get' will be streamed bytes until it returns 'Done' or 'Fail'.
--
-- If 'Get' succeed it will return the data read and unconsumed part of the input stream.
-- If the 'Get' fails due to deserialization error or early termination of the input stream it raise an error.
sinkGet :: MonadThrow m => Get r -> Consumer BS.ByteString m r
sinkGet = mkSinkGet errorHandler terminationHandler
  where errorHandler msg = pipeError $ GetException msg
        terminationHandler f = case f BS.empty of
          Fail msg _ -> pipeError $ GetException msg
          Done r lo -> leftover lo >> return r
          Partial _ -> pipeError $ GetException "Failed reading: Internal error: unexpected Partial."

pipeError :: (MonadThrow m, MonadTrans t, Exception e) => e -> t m a
pipeError e = lift $ throwM e

-- | Convert a 'Put' into a 'Source'. Runs in constant memory.
sourcePut :: Monad m => Put -> Producer m BS.ByteString
sourcePut put = sourceLazy $ runPutLazy put

-- | Run a 'Putter' repeatedly on the input stream, producing a concatenated 'ByteString' stream.
conduitPut :: Monad m => Putter a -> Conduit a m BS.ByteString
conduitPut p = mapC $ runPut . p
