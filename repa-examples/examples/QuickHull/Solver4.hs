
module SolverFlow where
import Data.Array.Repa.Vector.Segd              (Segd)
import Data.Array.Repa.Vector                   as R
import Data.Array.Repa.Vector.Index             as R
import Data.Array.Repa.Vector.Operators.Zip     as R
import Data.Array.Repa.Vector.Operators.Unzip   as R
import Data.Array.Repa.Vector.Repr.Unboxed      as R
import qualified Data.Array.Repa.Vector.Segd    as Segd

-- | A point in the 2D plane.
type Point      = (Double, Double)



hsplit_l 
        :: Segd
        -> Vector U Point
        -> Vector U (Point, Point)
        -> (Segd, Vector U Point)

hsplit_l segd points lines
 = let  -- The determinate tells us how far from its line each point is.
        dets            :: Vector U Double
        !dets           = R.unflowP
                        $ R.zipWith detFn   points
                        $ R.replicates segd lines

        detFn xp@(xo, yo) ((x1, y1), (x2, y2))
         = (x1 - xo) * (y2 - yo) - (y1 - yo) * (x2 - xo)
        {-# INLINE detFn #-}

        -- Select points above the lines.
        above           :: Vector U Point
        !above          = R.unflowP 
                        $ R.pack
                        $ R.zip (R.map (> 0) dets) points

        -- Count how many points ended up in each segment.
        counts          :: Vector U Int
        !counts         = R.unflowP
                        $ R.counts (> 0) segd dets


        !flagsThen      = R.map (<= 0) counts
        !flagsElse      = R.map (> 0)  counts


        -- if-then-else ------------------------------------ THEN
        lines_then      = R.unflowP $ R.pack $ R.zip flagsThen lines

        hullSegd        = Segd.fromLengths
                        $ computeP $ R.replicate (ix1 (R.length lines_then)) 1

        hullPoints      = computeP 
                        $ R.map fst lines_then

        -- if-then-else ------------------------------------ ELSE
        !dets_else      = R.unflowP $ R.packs flagsElse segd dets
        !points_else    = R.unflowP $ R.packs flagsElse segd points

        !lines_else     = R.unflowP $ R.pack $ R.zip flagsElse lines
        !counts_else    = R.unflowP $ R.pack $ R.zip flagsElse counts

        !segd_else      = Segd.fromLengths 
                        $ R.unflowP $ R.pack $ R.zip flagsElse (Segd.lengths segd)

        -- Get the points furthest from each line
        --  The  (0, 0) below is a dummy point that will get replaced
        --  by the first point in the segment. 
        far (d0, p0) (d1, p1) 
         = d1 > d0

        !dpoints        = R.zip dets_else points_else
        !fars           = R.unflowP $ R.selects far (0, (0, 0)) segd_else dpoints


        !downSegd2      = Segd.fromLengths 
                        $ computeP $ R.replicate (ix1 (R.length counts_else)) 2

        !downSegd       = Segd.fromLengths
                        $ computeP $ replicate2 counts_else

        !segdAbove      = Segd.fromLengths counts_else

        -- Use the far points to make new splitting lines for the new segments.
        !downLines      = computeP  
                        $ R.flatten2 
                        $ R.map (\((p1, p2), (_, pFar)) -> ((p1, pFar), (pFar, p2)))
                        $ R.zip lines_else fars

        -- Recursive call
--        !(moarSegd, moarPoints)
--                = hsplit_l downSegd downPoints downLines

   in   error "finish me"


-- Until we implement this.
computeP arr = unflowP $ flow arr
