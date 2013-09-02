
module Data.Array.Repa.Plugin.ToGHC.Prim
        ( convertPrim
        , convertPolytypicPrim
        , isPolytypicPrimName)
where
import Data.Array.Repa.Plugin.Primitives
import Data.Array.Repa.Plugin.ToGHC.Type

import qualified HscTypes                as G
import qualified CoreSyn                 as G
import qualified Type                    as G
import qualified UniqSupply              as G

import qualified DDC.Core.Exp            as D
import qualified DDC.Core.Flow           as D
import qualified DDC.Core.Flow.Prim      as D
import qualified DDC.Core.Flow.Compounds as D

import qualified Data.Map                as Map


-------------------------------------------------------------------------------
-- | Convert a primop that has the same definition independent 
--   of its type arguments.
convertPrim 
        :: Env -> Env
        -> D.Name
        -> G.UniqSM (G.CoreExpr, G.Type)

convertPrim _kenv tenv n 
 = let prims    = envPrimitives tenv
   in case n of
        D.NameOpConcrete  D.OpConcreteRateOfSeries  -> return $ prim_rateOfSeries prims
        D.NameOpConcrete  D.OpConcreteNatOfRateNat  -> return $ prim_natOfRateNat prims
        D.NameOpConcrete (D.OpConcreteDown 4)       -> return $ prim_down4 prims
        D.NameOpConcrete (D.OpConcreteTail 4)       -> return $ prim_tail4 prims
        D.NameOpControl   D.OpControlGuard          -> return $ prim_guard prims
        D.NameOpControl  (D.OpControlSplit 4)       -> return $ prim_split4 prims

        -- ERROR: This isn't a primtive name,
        --        or we don't have an implementation for it.
        _ -> errorMissingPrim (envGuts tenv) n [] Nothing


-------------------------------------------------------------------------------
-- | Convert a primop that has a different definition depending on the type
--   argument. If primops handled by this function must be detected by
--   `isPolyTypicPrimName` below.
convertPolytypicPrim 
        :: Env -> Env
        -> D.Name -> [D.Type D.Name]
        -> G.UniqSM (G.CoreExpr, G.Type)

convertPolytypicPrim kenv _tenv n tsArg
 = let  prims    = envPrimitives kenv

        getPrim nn t 
         | t == D.tInt,      Just r <- Map.lookup nn (prim_baseInt  prims)    = r
         | t == D.tNat,      Just r <- Map.lookup nn (prim_baseWord prims)    = r
         | t == D.tFloat 32, Just r <- Map.lookup nn (prim_baseFloat32 prims) = r
         | t == D.tFloat 64, Just r <- Map.lookup nn (prim_baseFloat64 prims) = r
         | otherwise        
         = error $ "repa-plugin.convertPolytypicPrim: can't find prim for " ++ show nn

   in case n of
        -- Loop Combinators
        D.NameOpControl D.OpControlLoopN
         -> return $ prim_loop prims

        -- Arithmetic Primops
        D.NamePrimArith _
         |  [t]   <- tsArg       
         -> return $ getPrim n t

        -- Vector Primops
        D.NamePrimVec (D.PrimVecProj 4 ix)
         |  [t]  <- tsArg,      t == D.tFloat 32
         -> case ix of
                0       -> return $ prim_projFloatX4_0 prims
                1       -> return $ prim_projFloatX4_1 prims
                2       -> return $ prim_projFloatX4_2 prims
                3       -> return $ prim_projFloatX4_3 prims
                _       -> error "repa-plugin.convertPolytypicPrim: vec proj float failed."

        D.NamePrimVec _
         |  [t] <- tsArg
         -> return $ getPrim n t

        -- Store Primops
        D.NameOpConcrete (D.OpConcreteNext m)
         |  [tA, tK] <- tsArg, tA == D.tFloat 32, m == 4
         -> do  let (x, t) = prim_next4Float prims
                tK'     <- convertType kenv tK
                return  ( G.App x (G.Type tK')
                        , G.applyTy t tK')

         |  [tA, tK] <- tsArg
         ,  elem m [1, 4]
         -> do  let (x, t) = getPrim n tA
                tK'     <- convertType kenv tK
                return  ( G.App x (G.Type tK')
                        , G.applyTy t tK' )

        D.NameOpStore (D.OpStoreWriteVector m)
         |  [tA] <- tsArg, tA == D.tFloat 32, m == 4
         -> do  return  $ prim_writeVectorFloatX4 prims
                

         
        D.NameOpStore _
         | t : _ <- tsArg
         -> return $ getPrim n t

        -- ERROR: This isn't a primitive name,
        --        or we don't have an implementation for it,
        --        or the function `isPolytypicPrimName` tells lies.
        _  -> errorMissingPrim (envGuts kenv) n tsArg Nothing


-- | Check whether the function with this name must be handled polytypically. 
--   This needs to match all the names handled by `convertPolytypicPrim` above.
isPolytypicPrimName :: D.Name -> Bool
isPolytypicPrimName n
 = elem n       
        [ D.NamePrimArith       D.PrimArithAdd
        , D.NamePrimArith       D.PrimArithSub
        , D.NamePrimArith       D.PrimArithMul
        , D.NamePrimArith       D.PrimArithDiv
        , D.NamePrimArith       D.PrimArithMod
        , D.NamePrimArith       D.PrimArithRem
        , D.NamePrimArith       D.PrimArithEq
        , D.NamePrimArith       D.PrimArithNeq
        , D.NamePrimArith       D.PrimArithGt
        , D.NamePrimArith       D.PrimArithGe
        , D.NamePrimArith       D.PrimArithLt
        , D.NamePrimArith       D.PrimArithLe

        , D.NamePrimVec         (D.PrimVecNeg     4)
        , D.NamePrimVec         (D.PrimVecAdd     4)
        , D.NamePrimVec         (D.PrimVecSub     4)
        , D.NamePrimVec         (D.PrimVecMul     4)
        , D.NamePrimVec         (D.PrimVecDiv     4)
        , D.NamePrimVec         (D.PrimVecRep     4)
        , D.NamePrimVec         (D.PrimVecPack    4)
        , D.NamePrimVec         (D.PrimVecProj    4 0) 
        , D.NamePrimVec         (D.PrimVecProj    4 1) 
        , D.NamePrimVec         (D.PrimVecProj    4 2) 
        , D.NamePrimVec         (D.PrimVecProj    4 3) 
        , D.NamePrimVec         (D.PrimVecGather  4)
        , D.NamePrimVec         (D.PrimVecScatter 4)

        , D.NameOpConcrete      (D.OpConcreteNext 1)
        , D.NameOpConcrete      (D.OpConcreteNext 4)

        , D.NameOpControl       D.OpControlLoopN

        , D.NameOpStore         D.OpStoreNew
        , D.NameOpStore         D.OpStoreRead
        , D.NameOpStore         D.OpStoreWrite
        , D.NameOpStore         D.OpStoreNewVector
        , D.NameOpStore         (D.OpStoreReadVector  1)
        , D.NameOpStore         (D.OpStoreWriteVector 1)
        , D.NameOpStore         (D.OpStoreWriteVector 4)
        , D.NameOpStore         D.OpStoreSliceVector ]

        

-- | Complain that we couldn't find a primitive that we needed.
errorMissingPrim :: G.ModGuts -> D.Name -> [D.Type D.Name] -> Maybe String -> a
errorMissingPrim _guts _n _tsArgs (Just str)
 = error $ unlines
 $ map ("        " ++)
        [ ""
        , "repa-plugin:"
        , " Cannot find definition for primitive '" ++ str ++ "'"
        , ""
        , " When using the repa-plugin you must import a module that provides"
        , " implementations for the primitives used by the lowering transform."
        , ""
        , " This problem is likely caused by importing just the repa-series"
        , " module that contains the stream operators, but not the module that"
        , " contains the target primitives as well."
        , ""
        , " If you don't want to define your own primitives then try adding"
        , "  'import Data.Array.Repa.Series' to your client module."
        , ""
        , " This is a problem with the Repa plugin, and not GHC proper."
        , " You can ignore the following request to report this as a GHC bug." 
        , "" ]


errorMissingPrim _guts n tsArgs Nothing
 = error $ unlines
 $ map ("        " ++)
        [ ""
        , "repa-plugin:"
        , " No Haskell symbol name for Disciple Core Flow primitive:"
        , "  '" ++ show n ++ "'"
        , "  type arguments = " ++ show tsArgs
        , ""
        , " Please report this problem on the Repa bug tracker,"
        , "   or complain about it on the Repa mailing list."
        , ""
        , " This is a problem with the Repa plugin, and not GHC proper."
        , " You can ignore the following request to report this as a GHC bug." ]

