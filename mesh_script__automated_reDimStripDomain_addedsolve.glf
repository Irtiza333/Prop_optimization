#=========================================================================================================================================#
#                                                               ORCA MESH AUTOMATION                                                      #
#=========================================================================================================================================#

# Description: A generalized hybrid mesh generation for the ORCA propeller geometry. Only the surface mesh, inflation layers,                         
#              and unstructured transition are built here.
#              The script must be run with Startpoint_nogrid.pw which contains teh hub geometry. Basic gridding steps are as follows:
#                 - Load Startpoint_nogrid.pw and import blade geometry blade_OCC.iges
#                 - Assemble blade CAD into one model
#                 - Scale and rotate blade to agree with the hub of Startpoint_nogrid.pw
#                 - Assemble blade and hub into a watertight model
#                 - Trim tip region so ensure suitbale quilts for surface mesh?
#                 - Build surface mesh
#                 - Build inflation layers unstructured transition
#                 - Scale and rotate cylindircal grid in accordance with fixed hull volume mesh
#                 - Assign boundary, interface, and volume conditions
#                 - Export to .cas file

# Last Revised: 09/17/2025

#-----------------------------------------------------------------------------------------------------------------------------------------#
# TIP-CLOSURE COMPATIBILITY NOTE (blade CAD change)
#
# The blade CAD now exports a faired, self-closing TAPERED tip instead of the previous flat airfoil cap.
# X_blade.py appends a short band of tapered sections between R=0.999 and the true tip R=1.0
# (CLOSE_TIP / N_TIP_SECTIONS), and X_CAD.py closes that band with a small planar tip cap.
#
# Verified IGES compatibility against the previous geometry:
#   - The export still contains exactly 5 trimmed surfaces with the SAME Directory-Entry numbers
#     (TrimSurf-3, -29, -55, -81, -107). The quilt/connector setup below (quilt-blade1..5 and the
#     createOnDatabase connectors) therefore still applies unchanged.
#   - Only structural difference: the tip cap is now a planar trimmed surface (was a B-spline fill);
#     the five surfaces' DE numbering is identical, so quilt naming is preserved.
#
# What MAY need re-tuning (tip mesh quality only -- not topology):
#   - "Setting tip connector dimensions" (con dims ~30/20) and the tip/TE split fractions
#     (e.g. arc 21%/20%) below. The tip region is now smaller and tapered, so the tip domains
#     cover a smaller area.
#
# ACTION REQUIRED (could not be validated in the CAD environment): re-run this script in Pointwise
# on a freshly exported sample_blade*.iges, inspect the tip domains, then regenerate the CFX
# .def/.cas and re-run CFX.
#-----------------------------------------------------------------------------------------------------------------------------------------#


package require PWI_Glyph 8.23.2

#________________________________________LOADING STARTPOINT.PW AND IMPORTING OOC GENERATED BLADE________________________________________#

# Getting global directory       
set script_path [info script]
set script_dir [file dirname $script_path]

# Setting necessary file names and paths
set startpointname "Startpoint_nogrid.pw"
# set CADname "Camber_CAD/blade_OCC1.0.iges"
set CADname "sample_blade23.iges"
set PWname "ORCA_gridsample_blade3.pw"
set exportname "ORCA_gridsample_blade3.cas"
set startpoint_full_path [file join $script_dir $startpointname]
set CAD_full_path [file join $script_dir $CADname]
set PW_full_path [file join $script_dir $PWname]
set export_full_path [file join $script_dir $exportname]

pw::Application reset -keep Clipboard
set _TMP(mode_1) [pw::Application begin ProjectLoader]
  $_TMP(mode_1) initialize $startpoint_full_path
  $_TMP(mode_1) setAppendMode false
  $_TMP(mode_1) setRepairMode Defer
  $_TMP(mode_1) load
$_TMP(mode_1) end
unset _TMP(mode_1)

# Adjusting grid and nodal tolerances
pw::Grid setNodeTolerance 1.0e-07
pw::Grid setConnectorTolerance 1.0e-07
pw::Grid setGridPointTolerance 1.0e-09

puts $CAD_full_path

set _TMP(mode_1) [pw::Application begin DatabaseImport]
  $_TMP(mode_1) initialize -strict -type Automatic $CAD_full_path
  $_TMP(mode_1) setAttribute FileModelSizeFromFile false
  #$_TMP(mode_1) setAttribute FileUnits Meters
  $_TMP(mode_1) read
  $_TMP(mode_1) convert
$_TMP(mode_1) end
unset _TMP(mode_1)

#________________________________________IMPORT -- COMPLETE________________________________________#


#________________________________________ASSEMBLING BLADE INTO ONE MODEL________________________________________#

set _DB(1) [pw::DatabaseEntity getByName TrimSurf-55-model]
set _DB(2) [pw::DatabaseEntity getByName TrimSurf-107-model]
set _DB(3) [pw::DatabaseEntity getByName TrimSurf-3-model]
set _DB(4) [pw::DatabaseEntity getByName TrimSurf-81-model]
set _DB(5) [pw::DatabaseEntity getByName TrimSurf-29-model]
set _TMP(PW_1) [pw::Model assemble -reject _TMP(rejectEnts) -rejectReason _TMP(rejectReasons) -rejectLocation _TMP(rejectLocations) [list $_DB(1) $_DB(2) $_DB(3) $_DB(4) $_DB(5)]]
unset _TMP(rejectEnts)
unset _TMP(rejectReasons)
unset _TMP(rejectLocations)
unset _TMP(PW_1)

# Renaming blade model and quilts
set _DB(1) [pw::DatabaseEntity getByName TrimSurf-3-model]
$_DB(1) setName model-blade1
set _DB(2) [pw::DatabaseEntity getByName TrimSurf-29-quilt]
$_DB(2) setName quilt-blade1
set _DB(3) [pw::DatabaseEntity getByName TrimSurf-81-quilt]
$_DB(3) setName quilt-blade2
set _DB(4) [pw::DatabaseEntity getByName TrimSurf-3-quilt]
$_DB(4) setName quilt-blade3
set _DB(5) [pw::DatabaseEntity getByName TrimSurf-55-quilt]
$_DB(5) setName quilt-blade4
set _DB(6) [pw::DatabaseEntity getByName TrimSurf-107-quilt]
$_DB(6) setName quilt-blade5

#________________________________________BLADE ASSEMBLY -- COMPLETE________________________________________#


#________________________________________TRANSFORMING BLADE TO ALLIGN WITH COORDINATE SYSTEM OF HUB IN STARTPOINT.PW________________________________________#

# Scaling down
set _DB(6) [pw::DatabaseEntity getByName quilt-blade2]
set _DB(7) [pw::DatabaseEntity getByName quilt-blade5]
set _DB(8) [pw::DatabaseEntity getByName quilt-blade4]
set _DB(9) [pw::DatabaseEntity getByName quilt-blade1]
set _DB(10) [pw::DatabaseEntity getByName quilt-blade3]
set _DB(11) [pw::DatabaseEntity getByName model-blade1]
set _TMP(mode_1) [pw::Application begin Modify [list $_DB(6) $_DB(7) $_DB(8) $_DB(9) $_DB(10) $_DB(11)]]
  pw::Entity transform [pwu::Transform scaling -anchor {0 0 0} {0.001 0.001 0.001}] [$_TMP(mode_1) getEntities]
$_TMP(mode_1) end
unset _TMP(mode_1)

# Rotation and translation adjustments
set _DB(1) [pw::DatabaseEntity getByName model-blade1]
set _TMP(mode_1) [pw::Application begin Modify [list $_DB(1)]]
  pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 1 0} {0 0 0}]] -90] [$_TMP(mode_1) getEntities]
$_TMP(mode_1) end
unset _TMP(mode_1)

set _TMP(mode_1) [pw::Application begin Modify [list $_DB(1)]]
  pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 0 1} {0 0 0}]] -90] [$_TMP(mode_1) getEntities]
$_TMP(mode_1) end
unset _TMP(mode_1)

set _TMP(mode_1) [pw::Application begin Modify [list $_DB(1)]]
  pw::Entity transform [pwu::Transform translation {0 0 0.002}] [$_TMP(mode_1) getEntities]
$_TMP(mode_1) end
unset _TMP(mode_1)

#________________________________________TRANSFORM -- COMPLETE________________________________________#


#________________________________________ASSEMBLING BLADE AND HUB INTO ONE WATERTIGHT MODEL________________________________________#

# Trimming hub and blade root
set _DB(1) [pw::DatabaseEntity getByName model-blade1]
set _DB(2) [pw::DatabaseEntity getByName quilt-hub1]
set _DB(3) [pw::DatabaseEntity getByName model-hub1]
set _TMP(mode_1) [pw::Application begin Modify [list $_DB(1) $_DB(2)]]
  pw::Quilt trimBySurfaces -mode Both -keep Both [list $_DB(1)] [list $_DB(2)]
$_TMP(mode_1) end
unset _TMP(mode_1)

# Deleting trimmed regions
set _DB(4) [pw::DatabaseEntity getByName quilt-blade3-split-2]
set _DB(5) [pw::DatabaseEntity getByName quilt-blade4-split-2]
set _DB(6) [pw::DatabaseEntity getByName quilt-blade1-split-2]
set _DB(7) [pw::DatabaseEntity getByName quilt-blade2-split-2]
pw::Entity delete [list $_DB(4) $_DB(5) $_DB(6) $_DB(7)]

### Ensuring naming is correct for hub entities ###

# Attempt to get both possible hub quilts
set quilt1 [pw::DatabaseEntity getByName quilt-hub1-split-1]
set quilt2 [pw::DatabaseEntity getByName quilt-hub1-split-2]

# Get bounding boxes for both
set bbox1 [$quilt1 getExtents]
set bbox2 [$quilt2 getExtents]
set bbox1_flat [concat {*}$bbox1]
set bbox2_flat [concat {*}$bbox2]

# Compute height and compare (based on the knowledge that the hub is always going to have larger height that the root section)
set dz1 [expr {[lindex $bbox1_flat 5] - [lindex $bbox1_flat 2]}]
set dz2 [expr {[lindex $bbox2_flat 5] - [lindex $bbox2_flat 2]}]

# Use height to determine which is the actual hub
if {$dz1 > $dz2} {
    # quilt1 is the real hub
    set _DB(8) $quilt2
    pw::Entity delete [list $_DB(8)]
} else {
    # quilt2 is the real hub
    set _DB(1) $quilt2
    set _DB(8) $quilt1
    pw::Entity delete [list $_DB(8)]
    $_DB(1) setName quilt-hub1-split-1
}

# Model assembly
set _TMP(PW_1) [pw::Model assemble -reject _TMP(rejectEnts) -rejectReason _TMP(rejectReasons) -rejectLocation _TMP(rejectLocations) [list $_DB(1) $_DB(3)]]
unset _TMP(rejectEnts)
unset _TMP(rejectReasons)
unset _TMP(rejectLocations)
unset _TMP(PW_1)

# Renaming model and quilts
set _DB(1) [pw::DatabaseEntity getByName model-hub1]
$_DB(1) setName model-prop
set _DB(2) [pw::DatabaseEntity getByName quilt-hub1-split-1]
$_DB(2) setName quilt-hub1
set _DB(2) [pw::DatabaseEntity getByName quilt-blade1-split-1]
$_DB(2) setName quilt-blade1
set _DB(2) [pw::DatabaseEntity getByName quilt-blade2-split-1]
$_DB(2) setName quilt-blade2
set _DB(2) [pw::DatabaseEntity getByName quilt-blade3-split-1]
$_DB(2) setName quilt-blade3
set _DB(2) [pw::DatabaseEntity getByName quilt-blade4-split-1]
$_DB(2) setName quilt-blade4

#________________________________________TOTAL ASSEMBLY -- COMPLETE________________________________________#


#________________________________________BUILDING SURFACE MESH________________________________________#

pw::Display setCurrentLayer 4

# Creating connectors on blade quilt boundaries
set _DB(1) [pw::DatabaseEntity getByName quilt-blade3]
set _DB(2) [pw::DatabaseEntity getByName model-prop]
set _DB(3) [pw::DatabaseEntity getByName quilt-blade5]
set _DB(4) [pw::DatabaseEntity getByName quilt-blade2]
set _DB(5) [pw::DatabaseEntity getByName quilt-blade4]
set _DB(6) [pw::DatabaseEntity getByName quilt-blade1]
set _TMP(PW_1) [pw::Connector createOnDatabase -parametricConnectors Aligned -merge 0 -type Unstructured -reject _TMP(unused) [list $_DB(3) $_DB(4) $_DB(5) $_DB(1) $_DB(6)]]
unset _TMP(unused)
unset _TMP(PW_1)

# Splitting LE connectors
set _CN(1) [pw::GridEntity getByName con-6]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(1) getParameter -arc [expr {0.01 * 95.2}]]
set _TMP(PW_1) [$_CN(1) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)
set _CN(2) [pw::GridEntity getByName con-7]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(2) getParameter -arc [expr {0.01 * 4.8}]]
set _TMP(PW_1) [$_CN(2) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)

# Creating connector near tip and projecting it to LE quilt
set _TMP(mode_1) [pw::Application begin Create]
  set _CN(1) [pw::GridEntity getByName con-7-split-1]
  set _TMP(PW_1) [pw::SegmentSpline create]
  set _CN(3) [pw::GridEntity getByName con-6-split-1]
  $_TMP(PW_1) addPoint [$_CN(1) getPosition -arc 1]
  $_TMP(PW_1) addPoint [$_CN(3) getPosition -arc 1]
  set _CN(5) [pw::Connector create]
  $_CN(5) addSegment $_TMP(PW_1)
  unset _TMP(PW_1)
$_TMP(mode_1) end
unset _TMP(mode_1)

### Procedure for dimensioning a connector ###
proc dimCon {conSet conName dim} {
  set conSet [pw::GridEntity getByName $conName]
  $conSet setDimension $dim
}

# Setting LE connector dimensions
dimCon _CN(1) con-6-split-1 100
dimCon _CN(2) con-7-split-2 100
dimCon _CN(3) con-13 20
dimCon _CN(4) con-5 20
dimCon _CN(5) con-10 20

### Procedures for connector near tip to ensure suitable database associativity ###
proc projectCon {} {
  set _CN(1) [pw::GridEntity getByName con-13]
  set _DB(1) [pw::DatabaseEntity getByName quilt-blade3]
  set _TMP(PW_1) [subst [list $_CN(1)]]
  set _TMP(mode_1) [pw::Application begin Modify $_TMP(PW_1)]
    set _TMP(PW_2) [list $_DB(1)]
    pw::Entity project -type ClosestPoint -interior -fit 0.001 $_TMP(PW_1) $_TMP(PW_2)
    unset _TMP(PW_2)
  $_TMP(mode_1) end
  unset _TMP(mode_1)
  unset _TMP(PW_1)
}
proc equalspaceCon {} {
  set _CN(1) [pw::GridEntity getByName con-13]
  set _DB(1) [pw::DatabaseEntity getByName quilt-blade3]
  set _TMP(mode_1) [pw::Application begin Modify [list $_CN(1)]]
    $_CN(1) replaceDistribution 1 [pw::DistributionTanh create]
    [$_CN(1) getDistribution 1] setBeginSpacing 0.0
    [$_CN(1) getDistribution 1] setEndSpacing 0.0
  $_TMP(mode_1) end
  unset _TMP(mode_1)
}

# Adjusting connector near tip to ensure suitable database associativity
projectCon
equalspaceCon
projectCon
equalspaceCon
projectCon
equalspaceCon

projectCon
equalspaceCon
projectCon
equalspaceCon
projectCon
equalspaceCon
projectCon
equalspaceCon


# Assembling and solving LE doamin
set _CN(1) [pw::GridEntity getByName con-5]
set _CN(2) [pw::GridEntity getByName con-6-split-1]
set _CN(3) [pw::GridEntity getByName con-13]
set _CN(4) [pw::GridEntity getByName con-7-split-2]
set _TMP(PW_1) [pw::DomainStructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(1) $_CN(2) $_CN(3) $_CN(4)]]
unset _TMP(unusedCons)
unset _TMP(PW_1)
set _DM(1) [pw::GridEntity getByName dom-1]
set _TMP(mode_1) [pw::Application begin EllipticSolver [list $_DM(1)]]
  $_TMP(mode_1) setActiveSubGrids $_DM(1) [list]
  $_TMP(mode_1) run 42
$_TMP(mode_1) end
unset _TMP(mode_1)

# Removing unneceassry tip connectors
set _CN(1) [pw::GridEntity getByName con-2]
set _CN(2) [pw::GridEntity getByName con-4]
pw::Entity delete [list $_CN(1) $_CN(2)]

# Joining tip and TE connectors
set _CN(1) [pw::GridEntity getByName con-11]
set _CN(2) [pw::GridEntity getByName con-9]
set _CN(3) [pw::GridEntity getByName con-1]
set _CN(4) [pw::GridEntity getByName con-7-split-1]
set _CN(5) [pw::GridEntity getByName con-3]
set _CN(6) [pw::GridEntity getByName con-6-split-2]
set _TMP(PW_1) [pw::Connector join [list $_CN(1) $_CN(2) $_CN(3) $_CN(4) $_CN(5) $_CN(6)]]
unset _TMP(PW_1)

# Splitting TE/tip joined connectors
set _CN(1) [pw::GridEntity getByName con-6-split-2]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(1) getParameter -arc [expr {0.01 * 21    }]]
set _TMP(PW_1) [$_CN(1) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)

set _CN(1) [pw::GridEntity getByName con-7-split-1]
set _CN(3) [pw::GridEntity getByName con-6-split-2-split-1]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(1) getParameter -closest [pw::Application getXYZ [$_CN(1) closestPoint [$_CN(3) getPosition -arc 1]]]]
set _TMP(PW_1) [$_CN(1) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)

# Creating connector across tip/TE region
set _TMP(mode_1) [pw::Application begin Create]
  set _CN(1) [pw::GridEntity getByName con-6-split-2-split-2]
  set _TMP(PW_1) [pw::SegmentSpline create]
  set _CN(3) [pw::GridEntity getByName con-7-split-1-split-2]
  $_TMP(PW_1) addPoint [$_CN(1) getPosition -arc 0]
  $_TMP(PW_1) addPoint [$_CN(3) getPosition -arc 0]
  set _CN(5) [pw::Connector create]
  $_CN(5) addSegment $_TMP(PW_1)
  unset _TMP(PW_1)
$_TMP(mode_1) end
unset _TMP(mode_1)

# Setting tip connector dimensions (just changed from 100 to 30)
set _CN(1) [pw::GridEntity getByName con-7-split-1-split-1]
$_CN(1) setDimension 30 
set _CN(2) [pw::GridEntity getByName con-6-split-2-split-1]
$_CN(2) setDimension 30
set _CN(3) [pw::GridEntity getByName con-14]
$_CN(3) setDimension 20

# Creating tip domain
set _CN(4) [pw::GridEntity getByName con-13]
set _TMP(PW_1) [pw::DomainStructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(1) $_CN(2) $_CN(3) $_CN(4)]]
unset _TMP(unusedCons)
unset _TMP(PW_1)

# Splitting TE connectors
set _CN(1) [pw::GridEntity getByName con-6-split-2-split-2]
set _CN(2) [pw::GridEntity getByName con-7-split-1-split-2]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(1) getParameter -arc [expr {0.01 * 20}]]
set _TMP(PW_1) [$_CN(1) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)

set _CN(6) [pw::GridEntity getByName con-6-split-2-split-2-split-1]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(2) getParameter -closest [pw::Application getXYZ [$_CN(2) closestPoint [$_CN(6) getPosition -arc 1]]]]
set _TMP(PW_1) [$_CN(2) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)

# Creating connector across TE
set _TMP(mode_1) [pw::Application begin Create]
  set _TMP(PW_1) [pw::SegmentSurfaceSpline create]
  set _DB(2) [pw::DatabaseEntity getByName quilt-blade4]
  set _CN(3) [pw::GridEntity getByName con-6-split-2-split-2-split-1]
  set _CN(4) [pw::GridEntity getByName con-7-split-1-split-2-split-1]
  $_TMP(PW_1) addPoint [pw::Database closestPoint -explicit [list $_DB(2)] [$_CN(3) getPosition -arc 1]]
  $_TMP(PW_1) addPoint [[$_TMP(PW_1) getQuilt] closestPoint -surfaces [$_TMP(PW_1) getSurface] [$_CN(4) getPosition -arc 1]]
  $_TMP(PW_1) setSlope Linear
  set _CN(5) [pw::Connector create]
  $_CN(5) addSegment $_TMP(PW_1)
  unset _TMP(PW_1)
$_TMP(mode_1) end
unset _TMP(mode_1)

# Splitting connector just created
set _CN(7) [pw::GridEntity getByName con-15]
$_CN(7) setDimension 20
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(7) getParameter -arc [expr {0.01 * 49.100000000000001}]]
set _TMP(PW_1) [$_CN(7) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)

# Distributing connector just created
set _CN(1) [pw::GridEntity getByName con-15-split-1]
set _CN(2) [pw::GridEntity getByName con-15-split-2]
set _TMP(mode_1) [pw::Application begin Modify [list $_CN(2) $_CN(1)]]
  set _TMP(PW_1) [$_CN(1) getDistribution 1]
  $_TMP(PW_1) setEndSpacing 0.0001
  unset _TMP(PW_1)
  set _TMP(PW_1) [$_CN(2) getDistribution 1]
  $_TMP(PW_1) setBeginSpacing 0.0001
  unset _TMP(PW_1)
$_TMP(mode_1) end
unset _TMP(mode_1)

# Copying spacing of connector just created to blade tip
set _CN(3) [pw::GridEntity getByName con-14]
set _TMP(mode_1) [pw::Application begin Modify [list $_CN(3)]]
  set _TMP(dist_1) [pw::DistributionGeneral create [list [list $_CN(1) 1] [list $_CN(2) 1]]]
  $_TMP(dist_1) setBeginSpacing 0
  $_TMP(dist_1) setEndSpacing 0
  $_TMP(dist_1) setVariable [[$_CN(3) getDistribution 1] getVariable]
  $_CN(3) setDistribution -lockEnds 1 $_TMP(dist_1)
  unset _TMP(dist_1)
$_TMP(mode_1) end
unset _TMP(mode_1)

# Setting dimension for TE/tip and TE connectors
set _CN(4) [pw::GridEntity getByName con-6-split-2-split-2-split-1]
$_CN(4) setDimension 30 
set _CN(5) [pw::GridEntity getByName con-7-split-1-split-2-split-1]
$_CN(5) setDimension 30 
set _CN(6) [pw::GridEntity getByName con-6-split-2-split-2-split-2]
$_CN(6) setDimension 100
set _CN(7) [pw::GridEntity getByName con-7-split-1-split-2-split-2]
$_CN(7) setDimension 100

# Creating and solving (fixed) TE/tip domain
set _TMP(PW_1) [pw::DomainStructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(1) $_CN(2) $_CN(3) $_CN(4) $_CN(5)]]
unset _TMP(PW_1)

set _DM(1) [pw::GridEntity getByName dom-3]
set _TMP(mode_1) [pw::Application begin EllipticSolver [list $_DM(1)]]
  $_DM(1) setEllipticSolverAttribute ShapeConstraint Fixed
$_TMP(mode_1) end
unset _TMP(mode_1)

set _TMP(mode_1) [pw::Application begin EllipticSolver [list $_DM(1)]]
  $_TMP(mode_1) setActiveSubGrids $_DM(1) [list]
  $_TMP(mode_1) run 100
$_TMP(mode_1) end
unset _TMP(mode_1)

# Creating TE domain
set _CN(8) [pw::GridEntity getByName con-10]
set _TMP(PW_1) [pw::DomainStructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(1) $_CN(2) $_CN(8) $_CN(6) $_CN(7)]]
unset _TMP(PW_1)

# Splitting LE connector
set _CN(10) [pw::GridEntity getByName con-6-split-1]
set _DM(10) [pw::GridEntity getByName dom-1]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(10) getParameter -closest [pw::Application getXYZ [$_CN(10) closestPoint [pw::Grid getPoint [list 20 93 $_DM(10)]]]]]
set _TMP(PW_1) [$_CN(10) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)

set _CN(20) [pw::GridEntity getByName con-7-split-2]
set _DB(50) [pw::DatabaseEntity getByName Line-110]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(20) getParameter -closest [pw::Application getXYZ [$_CN(20) closestPoint [pw::Grid getPoint [list 1 93 $_DM(10)]]]]]
set _TMP(PW_1) [$_CN(20) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)

# Splitting root cross section conncetor for H-topology
set _CN(30) [pw::GridEntity getByName con-8]
set _CN(40) [pw::GridEntity getByName con-12]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(30) getParameter -arc [expr {0.01 * 20}]]
lappend _TMP(split_params) [$_CN(30) getParameter -arc [expr {0.01 * 80}]]
set _TMP(PW_1) [$_CN(30) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(40) getParameter -arc [expr {0.01 * 20}]]
lappend _TMP(split_params) [$_CN(40) getParameter -arc [expr {0.01 * 80}]]
set _TMP(PW_1) [$_CN(40) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)

# Projecting root cross section to blade quilts
set _CN(1) [pw::GridEntity getByName con-8-split-3]
set _CN(2) [pw::GridEntity getByName con-8-split-2]
set _CN(3) [pw::GridEntity getByName con-8-split-1]
set _CN(4) [pw::GridEntity getByName con-12-split-3]
set _CN(5) [pw::GridEntity getByName con-12-split-2]
set _CN(6) [pw::GridEntity getByName con-12-split-1]
set _DB(1) [pw::DatabaseEntity getByName quilt-blade1]
set _DB(2) [pw::DatabaseEntity getByName quilt-blade2]
set _TMP(PW_1) [subst [list $_CN(1) $_CN(2) $_CN(3)]]
set _TMP(mode_1) [pw::Application begin Modify $_TMP(PW_1)]
  set _TMP(PW_2) [list $_DB(1)]
  pw::Entity project -type ClosestPoint -fit 0.001 -shape $_TMP(PW_1) $_TMP(PW_2)
  unset _TMP(PW_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
unset _TMP(PW_1)
set _TMP(PW_1) [subst [list $_CN(4) $_CN(5) $_CN(6)]]
set _TMP(mode_1) [pw::Application begin Modify $_TMP(PW_1)]
  set _TMP(PW_2) [list $_DB(2)]
  pw::Entity project -type ClosestPoint -fit 0.001 -shape $_TMP(PW_1) $_TMP(PW_2)
  unset _TMP(PW_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
unset _TMP(PW_1)


### Procedure for connector across upper or lower surface ###
proc midCon {quilt splitCon1 splitCon2} {
  set _TMP(mode_1) [pw::Application begin Create]
    set _TMP(PW_1) [pw::SegmentSurfaceSpline create]
    set _DB(2) [pw::DatabaseEntity getByName $quilt]
    set _DM(2) [pw::GridEntity getByName dom-1]
    set _DM(3) [pw::GridEntity getByName dom-4]
    $_TMP(PW_1) addPoint [pw::Database closestPoint -explicit [list $_DB(2)] [pw::Grid getPoint [list 20 89 $_DM(2)]]]
    $_TMP(PW_1) addPoint [[$_TMP(PW_1) getQuilt] closestPoint -surfaces [$_TMP(PW_1) getSurface] [pw::Grid getPoint [list 1 74 $_DM(3)]]]
    $_TMP(PW_1) setSlope Linear
    set _CN(5) [pw::Connector create]
    $_CN(5) addSegment $_TMP(PW_1)
    unset _TMP(PW_1)
  $_TMP(mode_1) end
  unset _TMP(mode_1)

  set _TMP(split_params) [list]
  lappend _TMP(split_params) [$_CN(5) getParameter -arc [expr {0.01 * 30}]]
  lappend _TMP(split_params) [$_CN(5) getParameter -arc [expr {0.01 * 70}]]
  set _TMP(PW_1) [$_CN(5) split $_TMP(split_params)]
  unset _TMP(PW_1)
  unset _TMP(split_params)
  set _CN(1) [pw::GridEntity getByName $splitCon1]
  pw::Entity delete [list $_CN(1)]
  set _CN(2) [pw::GridEntity getByName $splitCon2]
  pw::Entity delete [list $_CN(2)]

}

# Creating connector accross lower surface
midCon quilt-blade1 con-15-split-3 con-15-split-5

### Procedure for H-topology on upper and lower surface ###
proc HTop {quilt midCon LECon LEConPos TECon upperLECon RootCon1 RootCon2} {
  set _TMP(mode_1) [pw::Application begin Create]
    set _CN(1) [pw::GridEntity getByName $midCon]
    set _DB(2) [pw::DatabaseEntity getByName $quilt]
    set _TMP(PW_1) [pw::SegmentSpline create]
    set _CN(2) [pw::GridEntity getByName $LECon]
    $_TMP(PW_1) addPoint [$_CN(1) getPosition -arc 0]
    $_TMP(PW_1) addPoint [$_CN(2) getPosition -arc $LEConPos]
    set _CN(5) [pw::Connector create]
    $_CN(5) addSegment $_TMP(PW_1)
    unset _TMP(PW_1)
  $_TMP(mode_1) end
  unset _TMP(mode_1)
  set _TMP(PW_1) [subst [list $_CN(5)]]
  set _TMP(mode_1) [pw::Application begin Modify $_TMP(PW_1)]
    set _TMP(PW_2) [list $_DB(2)]
    pw::Entity project -type ClosestPoint -fit 0.001 -shape $_TMP(PW_1) $_TMP(PW_2)
    unset _TMP(PW_2)
  $_TMP(mode_1) end
  unset _TMP(mode_1)

  set _TMP(mode_1) [pw::Application begin Create]
    set _CN(4) [pw::GridEntity getByName $TECon]
    set _TMP(PW_1) [pw::SegmentSurfaceSpline create]
    $_TMP(PW_1) addPoint [$_CN(1) getPosition -arc 1]
    $_TMP(PW_1) addPoint [[$_TMP(PW_1) getQuilt] closestPoint -surfaces [$_TMP(PW_1) getSurface] [$_CN(4) getPosition -arc 1]]
    $_TMP(PW_1) setSlope Linear
    set _CN(10) [pw::Connector create]
    $_CN(10) addSegment $_TMP(PW_1)
    unset _TMP(PW_1)
  $_TMP(mode_1) end
  unset _TMP(mode_1)

set _TMP(mode_1) [pw::Application begin Create]
  set _TMP(PW_1) [pw::SegmentSurfaceSpline create]
  set _DB(20) [pw::DatabaseEntity getByName $quilt]
  set _CN(10) [pw::GridEntity getByName $upperLECon]
  set _CN(20) [pw::GridEntity getByName $midCon]
  set _CN(50) [pw::GridEntity getByName $RootCon1]
  set _CN(70) [pw::GridEntity getByName $RootCon2]
  $_TMP(PW_1) addPoint [pw::Database closestPoint -explicit [list $_DB(20)] [$_CN(10) getPosition -arc 0]]
  $_TMP(PW_1) addPoint [[$_TMP(PW_1) getQuilt] closestPoint -surfaces [$_TMP(PW_1) getSurface] [$_CN(70) getPosition -arc 1]]
  $_TMP(PW_1) setSlope Linear
  set _CN(19) [pw::Connector create]
  $_CN(19) addSegment $_TMP(PW_1)
  unset _TMP(PW_1)
  set _TMP(PW_1) [pw::SegmentSurfaceSpline create]
  $_TMP(PW_1) addPoint [$_CN(20) getPosition -arc 1]
  $_TMP(PW_1) addPoint [[$_TMP(PW_1) getQuilt] closestPoint -surfaces [$_TMP(PW_1) getSurface] [$_CN(50) getPosition -arc 1]]
  $_TMP(PW_1) setSlope Linear
  set _CN(27) [pw::Connector create]
  $_CN(27) addSegment $_TMP(PW_1)
  unset _TMP(PW_1)
$_TMP(mode_1) end
unset _TMP(mode_1)
}

# Creating upper surface H-topology
HTop quilt-blade1 con-15-split-4 con-13 1 con-6-split-2-split-2-split-1 con-15 con-8-split-2 con-8-split-1

# Creating connector accross upper surface
midCon quilt-blade2 con-19-split-1 con-19-split-3

# Creating lower surface H-topology
HTop quilt-blade2 con-19-split-2 con-13 0 con-7-split-1-split-2-split-1 con-19 con-12-split-1 con-12-split-2

# Dimensioning interior H-topology connectors
dimCon _CN(1) con-8-split-2 59
dimCon _CN(1) con-12-split-2 59
dimCon _CN(1) con-15-split-4 59
dimCon _CN(1) con-19-split-2 59
dimCon _CN(1) con-16 30
dimCon _CN(1) con-20 30
dimCon _CN(1) con-15 30
dimCon _CN(1) con-19 30
dimCon _CN(1) con-8-split-1 30
dimCon _CN(1) con-8-split-3 30
dimCon _CN(1) con-12-split-1 30
dimCon _CN(1) con-12-split-3 30
dimCon _CN(1) con-17 100
dimCon _CN(1) con-18 100
dimCon _CN(1) con-21 100
dimCon _CN(1) con-22 100

# Creating upper and lower surface domains
set _CN(1) [pw::GridEntity getByName con-6-split-1-split-1]
set _CN(2) [pw::GridEntity getByName con-6-split-1-split-2]
set _CN(3) [pw::GridEntity getByName con-8-split-1]
set _CN(4) [pw::GridEntity getByName con-15]
set _CN(5) [pw::GridEntity getByName con-17]
set _TMP(PW_1) [pw::DomainStructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(1) $_CN(2) $_CN(3) $_CN(4) $_CN(5)]]
unset _TMP(PW_1)
set _CN(6) [pw::GridEntity getByName con-7-split-2-split-1]
set _CN(7) [pw::GridEntity getByName con-7-split-2-split-2]
set _CN(8) [pw::GridEntity getByName con-12-split-3]
set _CN(9) [pw::GridEntity getByName con-19]
set _CN(10) [pw::GridEntity getByName con-21]
set _TMP(PW_1) [pw::DomainStructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(6) $_CN(7) $_CN(8) $_CN(9) $_CN(10)]]
unset _TMP(PW_1)
set _CN(11) [pw::GridEntity getByName con-8-split-2]
set _CN(12) [pw::GridEntity getByName con-15-split-4]
set _CN(13) [pw::GridEntity getByName con-18]
set _TMP(PW_1) [pw::DomainStructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(5) $_CN(11) $_CN(12) $_CN(13)]]
unset _TMP(PW_1)
set _CN(14) [pw::GridEntity getByName con-16]
set _CN(15) [pw::GridEntity getByName con-6-split-2-split-2-split-1]
set _CN(16) [pw::GridEntity getByName con-15-split-4]
set _CN(17) [pw::GridEntity getByName con-6-split-2-split-1]
set _TMP(PW_1) [pw::DomainStructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(4) $_CN(14) $_CN(15) $_CN(16) $_CN(17)]]
unset _TMP(PW_1)
set _CN(18) [pw::GridEntity getByName con-8-split-3]
set _CN(19) [pw::GridEntity getByName con-6-split-2-split-2-split-2]
set _TMP(PW_1) [pw::DomainStructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(13) $_CN(14) $_CN(18) $_CN(19)]]
unset _TMP(PW_1)
set _CN(20) [pw::GridEntity getByName con-19-split-2]
set _CN(21) [pw::GridEntity getByName con-22]
set _CN(22) [pw::GridEntity getByName con-12-split-2]
set _TMP(PW_1) [pw::DomainStructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(20) $_CN(21) $_CN(22) $_CN(10)]]
unset _TMP(PW_1)
set _CN(23) [pw::GridEntity getByName con-20]
set _CN(24) [pw::GridEntity getByName con-7-split-1-split-1]
set _CN(25) [pw::GridEntity getByName con-19-split-2]
set _CN(26) [pw::GridEntity getByName con-7-split-1-split-2-split-1]
set _TMP(PW_1) [pw::DomainStructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(23) $_CN(24) $_CN(25) $_CN(26) $_CN(9)]]
unset _TMP(PW_1)
set _CN(27) [pw::GridEntity getByName con-7-split-1-split-2-split-2]
set _CN(28) [pw::GridEntity getByName con-12-split-1]
set _TMP(PW_1) [pw::DomainStructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(27) $_CN(28) $_CN(23) $_CN(21)]]
unset _TMP(PW_1)

# Redimensioning thin domain
set _TMP(mode_1) [pw::Application begin Dimension]
  set _CN(1) [pw::GridEntity getByName con-13]
  set _CN(2) [pw::GridEntity getByName con-14]
  set _CN(3) [pw::GridEntity getByName con-5]
  set _CN(4) [pw::GridEntity getByName con-10]
  set _TMP(PW_1) [pw::Collection create]
  $_TMP(PW_1) set [list $_CN(3)]
  $_TMP(PW_1) do setDimension -resetDistribution 5
  $_TMP(PW_1) delete
  unset _TMP(PW_1)
  $_TMP(mode_1) balance -resetGeneralDistributions
  set _CN(5) [pw::GridEntity getByName con-8-split-1]
  set _CN(6) [pw::GridEntity getByName con-8-split-3]
  set _CN(7) [pw::GridEntity getByName con-15]
  set _CN(8) [pw::GridEntity getByName con-16]
  set _CN(9) [pw::GridEntity getByName con-6-split-2-split-2-split-2]
  set _CN(10) [pw::GridEntity getByName con-7-split-1-split-2-split-2]
  set _CN(11) [pw::GridEntity getByName con-21]
  set _CN(12) [pw::GridEntity getByName con-22]
  set _CN(13) [pw::GridEntity getByName con-17]
  set _CN(14) [pw::GridEntity getByName con-18]
  set _CN(15) [pw::GridEntity getByName con-8-split-2]
  set _CN(16) [pw::GridEntity getByName con-19-split-2]
  set _CN(17) [pw::GridEntity getByName con-15-split-4]
  set _CN(18) [pw::GridEntity getByName con-12-split-2]
  set _CN(19) [pw::GridEntity getByName con-6-split-1-split-1]
  set _CN(20) [pw::GridEntity getByName con-7-split-2-split-2]
  set _CN(21) [pw::GridEntity getByName con-6-split-1-split-2]
  set _CN(22) [pw::GridEntity getByName con-7-split-2-split-1]
  set _CN(23) [pw::GridEntity getByName con-12-split-3]
  set _CN(24) [pw::GridEntity getByName con-19]
  set _CN(25) [pw::GridEntity getByName con-20]
  set _CN(26) [pw::GridEntity getByName con-12-split-1]
  set _CN(27) [pw::GridEntity getByName con-6-split-2-split-1]
  set _CN(28) [pw::GridEntity getByName con-7-split-1-split-1]
  set _CN(29) [pw::GridEntity getByName con-6-split-2-split-2-split-1]
  set _CN(30) [pw::GridEntity getByName con-7-split-1-split-2-split-1]
  set _CN(31) [pw::GridEntity getByName con-15-split-1]
  set _TMP(PW_1) [pw::Collection create]
  $_TMP(PW_1) set [list $_CN(31)]
  $_TMP(PW_1) do setDimension -resetDistribution 3
  $_TMP(PW_1) delete
  unset _TMP(PW_1)
  $_TMP(mode_1) balance -resetGeneralDistributions
  set _CN(32) [pw::GridEntity getByName con-15-split-2]
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Dimension

set _TMP(mode_1) [pw::Application begin Modify [list $_CN(31)]]
  $_CN(31) replaceDistribution 1 [pw::DistributionTanh create]
  [$_CN(31) getDistribution 1] setBeginSpacing 0.0
  [$_CN(31) getDistribution 1] setEndSpacing 0.0
$_TMP(mode_1) abort
unset _TMP(mode_1)
set _TMP(mode_1) [pw::Application begin Modify [list $_CN(32) $_CN(1) $_CN(31) $_CN(2) $_CN(3) $_CN(4)]]
  $_CN(31) replaceDistribution 1 [pw::DistributionTanh create]
  [$_CN(31) getDistribution 1] setBeginSpacing 0.0
  [$_CN(31) getDistribution 1] setEndSpacing 0.0
  $_CN(4) replaceDistribution 1 [pw::DistributionTanh create]
  [$_CN(4) getDistribution 1] setBeginSpacing 0.0
  [$_CN(4) getDistribution 1] setEndSpacing 0.0
  $_CN(1) replaceDistribution 1 [pw::DistributionTanh create]
  [$_CN(1) getDistribution 1] setBeginSpacing 0.0
  [$_CN(1) getDistribution 1] setEndSpacing 0.0
  $_CN(32) replaceDistribution 1 [pw::DistributionTanh create]
  [$_CN(32) getDistribution 1] setBeginSpacing 0.0
  [$_CN(32) getDistribution 1] setEndSpacing 0.0
  $_CN(2) replaceDistribution 1 [pw::DistributionTanh create]
  [$_CN(2) getDistribution 1] setBeginSpacing 0.0
  [$_CN(2) getDistribution 1] setEndSpacing 0.0
  $_CN(3) replaceDistribution 1 [pw::DistributionTanh create]
  [$_CN(3) getDistribution 1] setBeginSpacing 0.0
  [$_CN(3) getDistribution 1] setEndSpacing 0.0
$_TMP(mode_1) end
unset _TMP(mode_1)

set _DM(1) [pw::GridEntity getByName dom-3]
set _TMP(mode_1) [pw::Application begin EllipticSolver [list $_DM(1)]]
  $_TMP(mode_1) setActiveSubGrids $_DM(1) [list]
  $_TMP(mode_1) run 5
  set _TMP(exam_1) [pw::Examine create DomainMinimumAngle]
  $_TMP(exam_1) addEntity [list $_DM(1)]
  $_TMP(exam_1) examine
  pw::CutPlane applyMetric {}
  $_TMP(exam_1) delete
  unset _TMP(exam_1)
  pw::CutPlane applyMetric {}
$_TMP(mode_1) end
unset _TMP(mode_1)


# added solve
set _DM(1) [pw::GridEntity getByName dom-2]
set _TMP(mode_1) [pw::Application begin EllipticSolver [list $_DM(1)]]
  $_TMP(mode_1) setActiveSubGrids $_DM(1) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(1) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(1) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(1) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(1) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(1) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(1) [list]
  $_TMP(mode_1) run 10
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Solve

set _DM(2) [pw::GridEntity getByName dom-3]
set _TMP(mode_1) [pw::Application begin EllipticSolver [list $_DM(2)]]
  $_DM(2) setEllipticSolverAttribute ShapeConstraint Free
  $_TMP(mode_1) setActiveSubGrids $_DM(2) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(2) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(2) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(2) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(2) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(2) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(2) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(2) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(2) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(2) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(2) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(2) [list]
  $_TMP(mode_1) run 10
  $_TMP(mode_1) setActiveSubGrids $_DM(2) [list]
  $_TMP(mode_1) run 10
$_TMP(mode_1) end
unset _TMP(mode_1)

#**One unstructured domain on hub still requires creation. It is built in following section post-inflation.

#________________________________________SURFACE MESH -- COMPLETE________________________________________#


#________________________________________BUILDING INLFATION________________________________________#

# Projecting root cross section connector to hub to ensure database-contrained inflation at root is possible 
# *Time consuming
set _CN(1) [pw::GridEntity getByName con-5]
set _CN(2) [pw::GridEntity getByName con-8-split-3]
set _CN(3) [pw::GridEntity getByName con-8-split-1]
set _CN(4) [pw::GridEntity getByName con-10]
set _CN(5) [pw::GridEntity getByName con-8-split-2]
set _CN(6) [pw::GridEntity getByName con-12-split-1]
set _CN(7) [pw::GridEntity getByName con-12-split-2]
set _CN(8) [pw::GridEntity getByName con-12-split-3]
set _DB(1) [pw::DatabaseEntity getByName quilt-hub1]
set _TMP(PW_1) [subst [list $_CN(2) $_CN(3) $_CN(4) $_CN(5) $_CN(6) $_CN(7) $_CN(8)]]; # removed _CN(1)
set _TMP(mode_1) [pw::Application begin Modify $_TMP(PW_1)]
  set _TMP(PW_2) [list $_DB(1)]
  pw::Entity project -type ClosestPoint -fit 0.001 $_TMP(PW_1) $_TMP(PW_2)
  unset _TMP(PW_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
unset _TMP(PW_1)

# Creating inflation
# *Time consuming
set _TMP(mode_1) [pw::Application begin Create]
  set _DM(1) [pw::GridEntity getByName dom-11]
  set _DM(2) [pw::GridEntity getByName dom-4]
  set _DM(3) [pw::GridEntity getByName dom-3]
  set _DM(4) [pw::GridEntity getByName dom-9]
  set _DM(5) [pw::GridEntity getByName dom-10]
  set _DM(6) [pw::GridEntity getByName dom-12]
  set _DM(7) [pw::GridEntity getByName dom-7]
  set _DM(8) [pw::GridEntity getByName dom-5]
  set _DM(9) [pw::GridEntity getByName dom-6]
  set _DM(10) [pw::GridEntity getByName dom-8]
  set _DM(11) [pw::GridEntity getByName dom-2]
  set _DM(12) [pw::GridEntity getByName dom-1]
  set _TMP(PW_1) [pw::FaceUnstructured createFromDomains [list $_DM(1) $_DM(2) $_DM(3) $_DM(4) $_DM(5) $_DM(6) $_DM(7) $_DM(8) $_DM(9) $_DM(10) $_DM(11) $_DM(12)]]
  set _TMP(face_1) [lindex $_TMP(PW_1) 0]
  unset _TMP(PW_1)
  set _BL(1) [pw::BlockExtruded create]
  $_BL(1) addFace $_TMP(face_1)
$_TMP(mode_1) end
unset _TMP(mode_1)
set _TMP(mode_1) [pw::Application begin ExtrusionSolver [list $_BL(1)]]
  $_TMP(mode_1) setKeepFailingStep true
  $_BL(1) setExtrusionBoundaryCondition [list 1 1] DatabaseConstrained [list $_DB(1)]
  $_BL(1) setExtrusionBoundaryCondition [list 1 2] DatabaseConstrained [list $_DB(1)]
  $_BL(1) setExtrusionBoundaryCondition [list 1 3] DatabaseConstrained [list $_DB(1)]
  $_BL(1) setExtrusionBoundaryCondition [list 1 4] DatabaseConstrained [list $_DB(1)]
  $_BL(1) setExtrusionBoundaryCondition [list 1 5] DatabaseConstrained [list $_DB(1)]
  $_BL(1) setExtrusionBoundaryCondition [list 1 6] DatabaseConstrained [list $_DB(1)]
  $_BL(1) setExtrusionBoundaryCondition [list 1 7] DatabaseConstrained [list $_DB(1)]
  $_BL(1) setExtrusionBoundaryCondition [list 1 8] DatabaseConstrained [list $_DB(1)]
  $_BL(1) setExtrusionSolverAttribute NormalInitialStepSize 3.5e-06
  $_BL(1) setExtrusionSolverAttribute SpacingGrowthFactor 1.2
  $_TMP(mode_1) run 39
$_TMP(mode_1) end
unset _TMP(mode_1)
unset _TMP(face_1)

# Moving inflation block to inflation_blk layer
set _BL(1) [pw::GridEntity getByName blk-1]
set _TMP(PW_1) [pw::Collection create]
$_TMP(PW_1) set [list $_BL(1)]
$_TMP(PW_1) do setLayer 5
$_TMP(PW_1) delete
unset _TMP(PW_1)



# #________________________________________INLFATION -- COMPLETE________________________________________#

# #____________________________CONFIGURING FOR HULL GEOMETRY________________________________________________________________________#

# splitting hub for accurate sizing
set _TMP(mode_1) [pw::Application begin Create]
  set _DB(1) [pw::Plane create]
  $_DB(1) setConstant -Z -0.27000000000000002
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Planes

pw::Application clearClipboard
pw::Application setClipboard [list $_DB(1)]
pw::Application markUndoLevel Copy

set _TMP(mode_1) [pw::Application begin Paste]
  set _TMP(PW_1) [$_TMP(mode_1) getEntities]
  set _TMP(mode_2) [pw::Application begin Modify $_TMP(PW_1)]
    pw::Entity transform [pwu::Transform translation {0 0 0.625}] [$_TMP(mode_2) getEntities]
  $_TMP(mode_2) end
  unset _TMP(mode_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Paste

unset _TMP(PW_1)
set _DB(2) [pw::DatabaseEntity getByName quilt-hub1]
set _DB(3) [pw::DatabaseEntity getByName model-prop]
set _DB(4) [pw::DatabaseEntity getByName plane-2]
set _TMP(mode_1) [pw::Application begin Modify [list $_DB(2) $_DB(4) $_DB(1)]]
  pw::Quilt trimBySurfaces -mode Both -keep Both [list $_DB(2)] [list $_DB(4) $_DB(1)]
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel {Trim By Surfaces}

set _DB(1) [pw::DatabaseEntity getByName quilt-hub1-split-3]
set _DB(2) [pw::DatabaseEntity getByName quilt-hub1-split-1]
set _TMP(PW_1) [pw::Connector createOnDatabase -parametricConnectors Aligned -merge 0 -type Unstructured -reject _TMP(unused) [list $_DB(1) $_DB(2)]]
unset _TMP(unused)
unset _TMP(PW_1)
pw::Application markUndoLevel {Connectors On DB Entities}

set _CN(1) [pw::GridEntity getByName con-81]
pw::Entity delete [list $_CN(1)]
pw::Application markUndoLevel Delete

set _CN(1) [pw::GridEntity getByName con-79]
pw::Entity delete [list $_CN(1)]
pw::Application markUndoLevel Delete

set _CN(1) [pw::GridEntity getByName con-78]
$_CN(1) setDimensionFromSpacing -resetDistribution 0.0079155124999999993
pw::CutPlane refresh
pw::Application markUndoLevel Dimension

set _CN(2) [pw::GridEntity getByName con-80]
$_CN(2) setDimensionFromSpacing -resetDistribution 0.0079155124999999993
pw::CutPlane refresh
pw::Application markUndoLevel Dimension

pw::Application clearClipboard
set _BL(1) [pw::GridEntity getByName blk-1]
pw::Application setClipboard [list $_BL(1)]
pw::Application markUndoLevel Copy

set _TMP(mode_1) [pw::Application begin Paste]
  set _TMP(PW_1) [$_TMP(mode_1) getEntities]
  set _TMP(mode_2) [pw::Application begin Modify $_TMP(PW_1)]
    pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 0 1} {0 0 0}]] 72] [$_TMP(mode_2) getEntities]
  $_TMP(mode_2) end
  unset _TMP(mode_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Paste

unset _TMP(PW_1)
set _TMP(mode_1) [pw::Application begin Paste]
  set _TMP(PW_1) [$_TMP(mode_1) getEntities]
  set _TMP(mode_2) [pw::Application begin Modify $_TMP(PW_1)]
    pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 0 1} {0 0 0}]] 144] [$_TMP(mode_2) getEntities]
  $_TMP(mode_2) end
  unset _TMP(mode_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Paste

unset _TMP(PW_1)
set _TMP(mode_1) [pw::Application begin Paste]
  set _TMP(PW_1) [$_TMP(mode_1) getEntities]
  set _TMP(mode_2) [pw::Application begin Modify $_TMP(PW_1)]
    pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 0 1} {0 0 0}]] -72] [$_TMP(mode_2) getEntities]
  $_TMP(mode_2) end
  unset _TMP(mode_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Paste

unset _TMP(PW_1)
set _TMP(mode_1) [pw::Application begin Paste]
  set _TMP(PW_1) [$_TMP(mode_1) getEntities]
  set _TMP(mode_2) [pw::Application begin Modify $_TMP(PW_1)]
    pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 0 1} {0 0 0}]] -144] [$_TMP(mode_2) getEntities]
  $_TMP(mode_2) end
  unset _TMP(mode_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Paste

unset _TMP(PW_1)

set _DM(1) [pw::GridEntity getByName dom-71]
set _DM(2) [pw::GridEntity getByName dom-91]
set _CN(1) [pw::GridEntity getByName con-80]
set _CN(2) [pw::GridEntity getByName con-12-split-8]
set _DM(3) [pw::GridEntity getByName dom-83]
set _DM(4) [pw::GridEntity getByName dom-74]
set _DM(5) [pw::GridEntity getByName dom-76]
set _DM(6) [pw::GridEntity getByName dom-82]
set _CN(3) [pw::GridEntity getByName con-12-split-7]
set _CN(4) [pw::GridEntity getByName con-143]
set _CN(5) [pw::GridEntity getByName con-156]
set _DM(7) [pw::GridEntity getByName dom-96]
set _DM(8) [pw::GridEntity getByName dom-94]
set _DM(9) [pw::GridEntity getByName dom-17]
set _DM(10) [pw::GridEntity getByName dom-24]
set _CN(6) [pw::GridEntity getByName con-35]
set _DM(11) [pw::GridEntity getByName dom-18]
set _DM(12) [pw::GridEntity getByName dom-32]
set _CN(7) [pw::GridEntity getByName con-36]
set _CN(8) [pw::GridEntity getByName con-39]
set _CN(9) [pw::GridEntity getByName con-61]
set _DM(13) [pw::GridEntity getByName dom-79]
set _CN(10) [pw::GridEntity getByName con-38]
set _DM(14) [pw::GridEntity getByName dom-19]
set _DM(15) [pw::GridEntity getByName dom-30]
set _CN(11) [pw::GridEntity getByName con-42]
set _CN(12) [pw::GridEntity getByName con-76]
set _DM(16) [pw::GridEntity getByName dom-50]
set _DM(17) [pw::GridEntity getByName dom-64]
set _DM(18) [pw::GridEntity getByName dom-44]
set _DM(19) [pw::GridEntity getByName dom-41]
set _DM(20) [pw::GridEntity getByName dom-61]
set _DM(21) [pw::GridEntity getByName dom-56]
set _DM(22) [pw::GridEntity getByName dom-36]
set _DM(23) [pw::GridEntity getByName dom-70]
set _DM(24) [pw::GridEntity getByName dom-69]
set _DM(25) [pw::GridEntity getByName dom-89]
set _DM(26) [pw::GridEntity getByName dom-90]
set _DB(1) [pw::DatabaseEntity getByName curve-182]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(1) getParameter -closest [pw::Application getXYZ [$_CN(1) closestPoint [$_CN(10) getPosition -arc 1]]]]
set _TMP(PW_1) [$_CN(1) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)
pw::Application markUndoLevel Split

set _CN(13) [pw::GridEntity getByName con-78]
set _TMP(PW_1) [pw::Connector synchronizeSpacings -minimum -growthRate 1.2 -returnDuplicates -undefined _TMP(undefinedDoms) [list $_CN(13)]]
unset _TMP(PW_1)
pw::Application markUndoLevel {Synchronize Spacings}

set _DM(27) [pw::GridEntity getByName dom-85]
set _DM(28) [pw::GridEntity getByName dom-77]
set _DM(29) [pw::GridEntity getByName dom-65]
set _CN(14) [pw::GridEntity getByName con-133]
set _DM(30) [pw::GridEntity getByName dom-84]
set _CN(15) [pw::GridEntity getByName con-12-split-9]
set _CN(16) [pw::GridEntity getByName con-147]
set _CN(17) [pw::GridEntity getByName con-7-split-2-split-6]
set _DM(31) [pw::GridEntity getByName dom-78]
set _DM(32) [pw::GridEntity getByName dom-14]
set _DM(33) [pw::GridEntity getByName dom-25]
set _DB(2) [pw::DatabaseEntity getByName curve-183]
set _CN(18) [pw::GridEntity getByName con-28]
set _DM(34) [pw::GridEntity getByName dom-13]
set _DM(35) [pw::GridEntity getByName dom-21]
set _CN(19) [pw::GridEntity getByName con-24]
set _CN(20) [pw::GridEntity getByName con-27]
set _CN(21) [pw::GridEntity getByName con-48]
set _DB(3) [pw::DatabaseEntity getByName quilt-hub1-split-2]
set _DM(36) [pw::GridEntity getByName dom-153]
set _DM(37) [pw::GridEntity getByName dom-142]
set _DM(38) [pw::GridEntity getByName dom-121]
set _DM(39) [pw::GridEntity getByName dom-133]
set _DM(40) [pw::GridEntity getByName dom-134]
set _DM(41) [pw::GridEntity getByName dom-101]
set _DM(42) [pw::GridEntity getByName dom-102]
set _DM(43) [pw::GridEntity getByName dom-122]
set _DM(44) [pw::GridEntity getByName dom-155]
set _DM(45) [pw::GridEntity getByName dom-135]
set _DM(46) [pw::GridEntity getByName dom-154]
set _DM(47) [pw::GridEntity getByName dom-117]
set _DM(48) [pw::GridEntity getByName dom-149]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(13) getParameter -closest [pw::Application getXYZ [$_CN(13) closestPoint [$_CN(18) getPosition -arc 1]]]]
set _TMP(PW_1) [$_CN(13) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)
pw::Application markUndoLevel Split

set _CN(22) [pw::GridEntity getByName con-80-split-1]
set _CN(23) [pw::GridEntity getByName con-80-split-2]
set _CN(24) [pw::GridEntity getByName con-78-split-1]
set _CN(25) [pw::GridEntity getByName con-78-split-2]
set _TMP(PW_1) [subst [list $_CN(22) $_CN(23) $_CN(24) $_CN(25)]]
set _TMP(mode_1) [pw::Application begin Modify $_TMP(PW_1)]
  set _TMP(PW_2) [list $_DB(3)]
  pw::Entity project -type ClosestPoint -fit 0.001 $_TMP(PW_1) $_TMP(PW_2)
  unset _TMP(PW_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Project

unset _TMP(PW_1)
set _TMP(mode_1) [pw::Application begin Create]
  set _TMP(PW_1) [pw::SegmentSurfaceSpline create]
  set _DB(4) [pw::DatabaseEntity getByName plane-2]
  set _DM(49) [pw::GridEntity getByName dom-34]
  set _DM(50) [pw::GridEntity getByName dom-43]
  set _DM(51) [pw::GridEntity getByName dom-40]
  set _DM(52) [pw::GridEntity getByName dom-63]
  set _DM(53) [pw::GridEntity getByName dom-54]
  set _DB(5) [pw::DatabaseEntity getByName quilt-hub1-split-3]
  set _DB(6) [pw::DatabaseEntity getByName plane-2-quilt]
  set _CN(26) [pw::GridEntity getByName con-165]
  $_TMP(PW_1) addPoint [$_CN(6) getPosition -arc 1]
  $_TMP(PW_1) addPoint [[$_TMP(PW_1) getQuilt] closestPoint -surfaces [$_TMP(PW_1) getSurface] [$_CN(22) getPosition -arc 1]]
  $_TMP(PW_1) setSlope Linear
  set _CN(27) [pw::Connector create]
  $_CN(27) addSegment $_TMP(PW_1)
  $_CN(27) calculateDimension
  unset _TMP(PW_1)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel {Create Connector}

set _TMP(mode_1) [pw::Application begin Create]
  set _TMP(PW_1) [pw::SegmentSurfaceSpline create]
  $_TMP(PW_1) delete
  unset _TMP(PW_1)
$_TMP(mode_1) abort
unset _TMP(mode_1)
set _TMP(mode_1) [pw::Application begin Create]
  set _TMP(PW_1) [pw::SegmentSurfaceSpline create]
  set _DB(7) [pw::DatabaseEntity getByName plane-1]
  set _DM(54) [pw::GridEntity getByName dom-59]
  set _DM(55) [pw::GridEntity getByName dom-5]
  set _DM(56) [pw::GridEntity getByName dom-1]
  set _DM(57) [pw::GridEntity getByName dom-6]
  set _DM(58) [pw::GridEntity getByName dom-26]
  set _DM(59) [pw::GridEntity getByName dom-10]
  set _DM(60) [pw::GridEntity getByName dom-27]
  set _DM(61) [pw::GridEntity getByName dom-62]
  set _DM(62) [pw::GridEntity getByName dom-42]
  set _DM(63) [pw::GridEntity getByName dom-58]
  set _DM(64) [pw::GridEntity getByName dom-39]
  set _DM(65) [pw::GridEntity getByName dom-38]
  set _DM(66) [pw::GridEntity getByName dom-37]
  set _DM(67) [pw::GridEntity getByName dom-33]
  set _DM(68) [pw::GridEntity getByName dom-57]
  set _DM(69) [pw::GridEntity getByName dom-53]
  set _CN(28) [pw::GridEntity getByName con-139]
  set _CN(29) [pw::GridEntity getByName con-158]
  set _DM(70) [pw::GridEntity getByName dom-15]
  set _DM(71) [pw::GridEntity getByName dom-47]
  set _DM(72) [pw::GridEntity getByName dom-7]
  set _DM(73) [pw::GridEntity getByName dom-51]
  $_TMP(PW_1) addPoint [$_CN(18) getPosition -arc 1]
  $_TMP(PW_1) addPoint [[$_TMP(PW_1) getQuilt] closestPoint -surfaces [$_TMP(PW_1) getSurface] [$_CN(24) getPosition -arc 1]]
  $_TMP(PW_1) setSlope Linear
  set _CN(30) [pw::Connector create]
  $_CN(30) addSegment $_TMP(PW_1)
  $_CN(30) calculateDimension
  unset _TMP(PW_1)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel {Create Connector}

set _TMP(mode_1) [pw::Application begin Create]
  set _TMP(PW_1) [pw::SegmentSurfaceSpline create]
  $_TMP(PW_1) delete
  unset _TMP(PW_1)
$_TMP(mode_1) abort
unset _TMP(mode_1)
pw::Application clearClipboard
pw::Application setClipboard [list $_CN(27) $_CN(30)]
pw::Application markUndoLevel Copy

set _TMP(mode_1) [pw::Application begin Paste]
  set _TMP(PW_1) [$_TMP(mode_1) getEntities]
  set _TMP(mode_2) [pw::Application begin Modify $_TMP(PW_1)]
    pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 0 1} {0 0 0}]] -72] [$_TMP(mode_2) getEntities]
  $_TMP(mode_2) end
  unset _TMP(mode_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Paste

unset _TMP(PW_1)
set _CN(31) [pw::GridEntity getByName con-291]
set _DM(74) [pw::GridEntity getByName dom-88]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(22) getParameter -closest [pw::Application getXYZ [$_CN(22) closestPoint [$_CN(31) getPosition -arc 1]]]]
set _TMP(PW_1) [$_CN(22) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)
pw::Application markUndoLevel Split

set _DB(8) [pw::DatabaseEntity getByName quilt-hub1-split-1]
set _DB(9) [pw::DatabaseEntity getByName plane-1-quilt]
set _CN(32) [pw::GridEntity getByName con-292]
set _DM(75) [pw::GridEntity getByName dom-20]
set _DM(76) [pw::GridEntity getByName dom-97]
set _DM(77) [pw::GridEntity getByName dom-103]
set _DM(78) [pw::GridEntity getByName dom-9]
set _DM(79) [pw::GridEntity getByName dom-123]
set _DM(80) [pw::GridEntity getByName dom-29]
set _DM(81) [pw::GridEntity getByName dom-105]
set _DM(82) [pw::GridEntity getByName dom-126]
set _DM(83) [pw::GridEntity getByName dom-106]
set _DM(84) [pw::GridEntity getByName dom-125]
set _DM(85) [pw::GridEntity getByName dom-12]
set _DM(86) [pw::GridEntity getByName dom-120]
set _DM(87) [pw::GridEntity getByName dom-128]
set _DM(88) [pw::GridEntity getByName dom-108]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(25) getParameter -closest [pw::Application getXYZ [$_CN(25) closestPoint [$_CN(32) getPosition -arc 1]]]]
set _TMP(PW_1) [$_CN(25) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)
pw::Application markUndoLevel Split

set _CN(1) [pw::GridEntity getByName con-290]
set _CN(2) [pw::GridEntity getByName con-289]
set _CN(3) [pw::GridEntity getByName con-292]
set _CN(4) [pw::GridEntity getByName con-291]
set _TMP(PW_1) [pw::Collection create]
$_TMP(PW_1) set [list $_CN(1) $_CN(2) $_CN(3) $_CN(4)]
$_TMP(PW_1) do setDimensionFromSpacing -resetDistribution 0.0050000000000000001
$_TMP(PW_1) delete
unset _TMP(PW_1)
pw::CutPlane refresh
pw::Application markUndoLevel Dimension

set _CN(5) [pw::GridEntity getByName con-80-split-1-split-2]
set _CN(6) [pw::GridEntity getByName con-78-split-2-split-1]
set _CN(7) [pw::GridEntity getByName con-45]
set _CN(8) [pw::GridEntity getByName con-24]
set _CN(9) [pw::GridEntity getByName con-39]
set _CN(10) [pw::GridEntity getByName con-42]
set _CN(11) [pw::GridEntity getByName con-201]
set _CN(12) [pw::GridEntity getByName con-207]
set _CN(13) [pw::GridEntity getByName con-205]
set _CN(14) [pw::GridEntity getByName con-203]
set _TMP(PW_1) [pw::DomainUnstructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(1) $_CN(2) $_CN(5) $_CN(3) $_CN(4) $_CN(6) $_CN(7) $_CN(8) $_CN(9) $_CN(10) $_CN(11) $_CN(12) $_CN(13) $_CN(14)]]
unset _TMP(unusedCons)
unset _TMP(PW_1)
pw::Application markUndoLevel {Assemble Domains}

pw::Application clearClipboard
set _DM(1) [pw::GridEntity getByName dom-161]
pw::Application setClipboard [list $_DM(1)]
pw::Application markUndoLevel Copy

set _TMP(mode_1) [pw::Application begin Paste]
  set _TMP(PW_1) [$_TMP(mode_1) getEntities]
  set _TMP(mode_2) [pw::Application begin Modify $_TMP(PW_1)]
    pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 0 1} {0 0 0}]] -72] [$_TMP(mode_2) getEntities]
  $_TMP(mode_2) end
  unset _TMP(mode_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Paste

unset _TMP(PW_1)
set _TMP(mode_1) [pw::Application begin Paste]
  set _TMP(PW_1) [$_TMP(mode_1) getEntities]
  set _TMP(mode_2) [pw::Application begin Modify $_TMP(PW_1)]
    pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 0 1} {0 0 0}]] -144] [$_TMP(mode_2) getEntities]
  $_TMP(mode_2) end
  unset _TMP(mode_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Paste

unset _TMP(PW_1)
set _TMP(mode_1) [pw::Application begin Paste]
  set _TMP(PW_1) [$_TMP(mode_1) getEntities]
  set _TMP(mode_2) [pw::Application begin Modify $_TMP(PW_1)]
    pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 0 1} {0 0 0}]] 72] [$_TMP(mode_2) getEntities]
  $_TMP(mode_2) end
  unset _TMP(mode_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Paste

unset _TMP(PW_1)
set _TMP(mode_1) [pw::Application begin Paste]
  set _TMP(PW_1) [$_TMP(mode_1) getEntities]
  set _TMP(mode_2) [pw::Application begin Modify $_TMP(PW_1)]
    pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 0 1} {0 0 0}]] 144] [$_TMP(mode_2) getEntities]
  $_TMP(mode_2) end
  unset _TMP(mode_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Paste

unset _TMP(PW_1)

set _CN(1) [pw::GridEntity getByName con-80-split-1-split-1]
set _CN(2) [pw::GridEntity getByName con-78-split-1]
set _CN(3) [pw::GridEntity getByName con-78-split-2-split-2]
set _CN(4) [pw::GridEntity getByName con-80-split-2]
pw::Entity delete [list $_CN(1) $_CN(2) $_CN(3) $_CN(4)]
pw::Application markUndoLevel Delete

set _DB(1) [pw::DatabaseEntity getByName model-prop]
pw::Entity delete [list $_DB(1)]
pw::Application markUndoLevel Delete

set _DM(1) [pw::GridEntity getByName dom-164]
set _DM(2) [pw::GridEntity getByName dom-161]
set _DM(3) [pw::GridEntity getByName dom-14]
set _DM(4) [pw::GridEntity getByName dom-17]
set _DM(5) [pw::GridEntity getByName dom-15]
set _DM(6) [pw::GridEntity getByName dom-16]
set _DM(7) [pw::GridEntity getByName dom-50]
set _DM(8) [pw::GridEntity getByName dom-52]
set _DM(9) [pw::GridEntity getByName dom-51]
set _DM(10) [pw::GridEntity getByName dom-45]
set _DM(11) [pw::GridEntity getByName dom-165]
set _DM(12) [pw::GridEntity getByName dom-163]
set _DM(13) [pw::GridEntity getByName dom-162]
set _DM(14) [pw::GridEntity getByName dom-19]
set _DM(15) [pw::GridEntity getByName dom-113]
set _DM(16) [pw::GridEntity getByName dom-110]
set _DM(17) [pw::GridEntity getByName dom-13]
set _DM(18) [pw::GridEntity getByName dom-18]
set _DM(19) [pw::GridEntity getByName dom-112]
set _DM(20) [pw::GridEntity getByName dom-20]
set _DM(21) [pw::GridEntity getByName dom-111]
set _DM(22) [pw::GridEntity getByName dom-82]
set _DM(23) [pw::GridEntity getByName dom-84]
set _DM(24) [pw::GridEntity getByName dom-77]
set _DM(25) [pw::GridEntity getByName dom-83]
set _DM(26) [pw::GridEntity getByName dom-49]
set _DM(27) [pw::GridEntity getByName dom-47]
set _DM(28) [pw::GridEntity getByName dom-46]
set _DM(29) [pw::GridEntity getByName dom-48]
set _DM(30) [pw::GridEntity getByName dom-114]
set _DM(31) [pw::GridEntity getByName dom-109]
set _DM(32) [pw::GridEntity getByName dom-115]
set _DM(33) [pw::GridEntity getByName dom-116]
set _DM(34) [pw::GridEntity getByName dom-81]
set _DM(35) [pw::GridEntity getByName dom-78]
set _DM(36) [pw::GridEntity getByName dom-79]
set _DM(37) [pw::GridEntity getByName dom-80]
set _DM(38) [pw::GridEntity getByName dom-144]
set _DM(39) [pw::GridEntity getByName dom-147]
set _DM(40) [pw::GridEntity getByName dom-145]
set _DM(41) [pw::GridEntity getByName dom-148]
set _DM(42) [pw::GridEntity getByName dom-146]
set _DM(43) [pw::GridEntity getByName dom-142]
set _DM(44) [pw::GridEntity getByName dom-141]
set _DM(45) [pw::GridEntity getByName dom-143]
set _BL(1) [pw::GridEntity getByName blk-5]
set _BL(2) [pw::GridEntity getByName blk-3]
set _BL(3) [pw::GridEntity getByName blk-4]
set _BL(4) [pw::GridEntity getByName blk-2]
set _BL(5) [pw::GridEntity getByName blk-1]
set _TMP(mode_1) [pw::Application begin Modify [list $_DM(12) $_DM(2) $_DM(13) $_BL(1) $_DM(3) $_DM(4) $_DM(5) $_DM(14) $_DM(30) $_DM(15) $_DM(16) $_DM(17) $_BL(2) $_DM(18) $_DM(31) $_DM(19) $_DM(20) $_DM(6) $_DM(32) $_DM(33) $_DM(21) $_BL(3) $_BL(4) $_BL(5) $_DM(22) $_DM(34) $_DM(23) $_DM(35) $_DM(36) $_DM(24) $_DM(37) $_DM(25) $_DM(38) $_DM(39) $_DM(40) $_DM(41) $_DM(42) $_DM(43) $_DM(44) $_DM(45) $_DM(26) $_DM(7) $_DM(8) $_DM(27) $_DM(28) $_DM(29) $_DM(9) $_DM(10) $_DM(11) $_DM(1)]]
  set _DM(46) [pw::GridEntity getByName dom-29]
  set _DM(47) [pw::GridEntity getByName dom-24]
  set _DM(48) [pw::GridEntity getByName dom-4]
  set _DM(49) [pw::GridEntity getByName dom-9]
  set _DM(50) [pw::GridEntity getByName dom-12]
  set _DM(51) [pw::GridEntity getByName dom-32]
  pw::Entity transform [pwu::Transform scaling -anchor {0 0 0} {0.14285714285000001 0.14285714285000001 0.14285714285000001}] [$_TMP(mode_1) getEntities]
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Scale

set _DB(1) [pw::DatabaseEntity getByName plane-2]
set _DB(2) [pw::DatabaseEntity getByName plane-1]
set _DB(3) [pw::DatabaseEntity getByName plane-2-quilt]
set _DB(4) [pw::DatabaseEntity getByName plane-1-quilt]
set _DB(5) [pw::DatabaseEntity getByName plane-2-model]
set _DB(6) [pw::DatabaseEntity getByName plane-1-model]
pw::Entity delete [list $_DB(1) $_DB(2) $_DB(3) $_DB(4) $_DB(5) $_DB(6)]
pw::Application markUndoLevel Delete

set _DM(1) [pw::GridEntity getByName dom-162]
set _DM(2) [pw::GridEntity getByName dom-163]
set _DM(3) [pw::GridEntity getByName dom-161]
set _DM(4) [pw::GridEntity getByName dom-114]
set _DM(5) [pw::GridEntity getByName dom-109]
set _DM(6) [pw::GridEntity getByName dom-115]
set _DM(7) [pw::GridEntity getByName dom-116]
set _DM(8) [pw::GridEntity getByName dom-144]
set _DM(9) [pw::GridEntity getByName dom-145]
set _DM(10) [pw::GridEntity getByName dom-142]
set _DM(11) [pw::GridEntity getByName dom-143]
set _DM(12) [pw::GridEntity getByName dom-19]
set _DM(13) [pw::GridEntity getByName dom-113]
set _DM(14) [pw::GridEntity getByName dom-110]
set _DM(15) [pw::GridEntity getByName dom-13]
set _DM(16) [pw::GridEntity getByName dom-18]
set _DM(17) [pw::GridEntity getByName dom-112]
set _DM(18) [pw::GridEntity getByName dom-20]
set _DM(19) [pw::GridEntity getByName dom-111]
set _DM(20) [pw::GridEntity getByName dom-81]
set _DM(21) [pw::GridEntity getByName dom-78]
set _DM(22) [pw::GridEntity getByName dom-79]
set _DM(23) [pw::GridEntity getByName dom-80]
set _DM(24) [pw::GridEntity getByName dom-147]
set _DM(25) [pw::GridEntity getByName dom-148]
set _DM(26) [pw::GridEntity getByName dom-146]
set _DM(27) [pw::GridEntity getByName dom-141]
set _DM(28) [pw::GridEntity getByName dom-165]
set _DM(29) [pw::GridEntity getByName dom-164]
set _DM(30) [pw::GridEntity getByName dom-14]
set _DM(31) [pw::GridEntity getByName dom-17]
set _DM(32) [pw::GridEntity getByName dom-15]
set _DM(33) [pw::GridEntity getByName dom-16]
set _DM(34) [pw::GridEntity getByName dom-82]
set _DM(35) [pw::GridEntity getByName dom-84]
set _DM(36) [pw::GridEntity getByName dom-77]
set _DM(37) [pw::GridEntity getByName dom-83]
set _DM(38) [pw::GridEntity getByName dom-49]
set _DM(39) [pw::GridEntity getByName dom-50]
set _DM(40) [pw::GridEntity getByName dom-52]
set _DM(41) [pw::GridEntity getByName dom-47]
set _DM(42) [pw::GridEntity getByName dom-46]
set _DM(43) [pw::GridEntity getByName dom-48]
set _DM(44) [pw::GridEntity getByName dom-51]
set _DM(45) [pw::GridEntity getByName dom-45]
set _BL(1) [pw::GridEntity getByName blk-5]
set _BL(2) [pw::GridEntity getByName blk-3]
set _BL(3) [pw::GridEntity getByName blk-4]
set _BL(4) [pw::GridEntity getByName blk-2]
set _BL(5) [pw::GridEntity getByName blk-1]
set _TMP(mode_1) [pw::Application begin Modify [list $_DM(2) $_DM(3) $_DM(1) $_BL(1) $_DM(30) $_DM(31) $_DM(32) $_DM(12) $_DM(4) $_DM(13) $_DM(14) $_DM(15) $_BL(2) $_DM(16) $_DM(5) $_DM(17) $_DM(18) $_DM(33) $_DM(6) $_DM(7) $_DM(19) $_BL(3) $_BL(4) $_BL(5) $_DM(34) $_DM(20) $_DM(35) $_DM(21) $_DM(22) $_DM(36) $_DM(23) $_DM(37) $_DM(8) $_DM(24) $_DM(9) $_DM(25) $_DM(26) $_DM(10) $_DM(27) $_DM(11) $_DM(38) $_DM(39) $_DM(40) $_DM(41) $_DM(42) $_DM(43) $_DM(44) $_DM(45) $_DM(28) $_DM(29)]]
  pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 1 0} {0 0 0}]] -90] [$_TMP(mode_1) getEntities]
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Rotate

set _TMP(mode_1) [pw::Application begin Modify [list $_DM(2) $_DM(3) $_DM(1) $_BL(1) $_DM(30) $_DM(31) $_DM(32) $_DM(12) $_DM(4) $_DM(13) $_DM(14) $_DM(15) $_BL(2) $_DM(16) $_DM(5) $_DM(17) $_DM(18) $_DM(33) $_DM(6) $_DM(7) $_DM(19) $_BL(3) $_BL(4) $_BL(5) $_DM(34) $_DM(20) $_DM(35) $_DM(21) $_DM(22) $_DM(36) $_DM(23) $_DM(37) $_DM(8) $_DM(24) $_DM(9) $_DM(25) $_DM(26) $_DM(10) $_DM(27) $_DM(11) $_DM(38) $_DM(39) $_DM(40) $_DM(41) $_DM(42) $_DM(43) $_DM(44) $_DM(45) $_DM(28) $_DM(29)]]
  set _DM(46) [pw::GridEntity getByName dom-154]
  set _DM(47) [pw::GridEntity getByName dom-89]
  set _DM(48) [pw::GridEntity getByName dom-21]
$_TMP(mode_1) abort
unset _TMP(mode_1)
set _TMP(mode_1) [pw::Application begin Modify [list $_DM(2) $_DM(3) $_DM(1) $_BL(1) $_DM(30) $_DM(31) $_DM(32) $_DM(12) $_DM(4) $_DM(13) $_DM(14) $_DM(15) $_BL(2) $_DM(16) $_DM(5) $_DM(17) $_DM(18) $_DM(33) $_DM(6) $_DM(7) $_DM(19) $_BL(3) $_BL(4) $_BL(5) $_DM(34) $_DM(20) $_DM(35) $_DM(21) $_DM(22) $_DM(36) $_DM(23) $_DM(37) $_DM(8) $_DM(24) $_DM(9) $_DM(25) $_DM(26) $_DM(10) $_DM(27) $_DM(11) $_DM(38) $_DM(39) $_DM(40) $_DM(41) $_DM(42) $_DM(43) $_DM(44) $_DM(45) $_DM(28) $_DM(29)]]
  set _DM(49) [pw::GridEntity getByName dom-123]
  set _DM(50) [pw::GridEntity getByName dom-12]
  set _DM(51) [pw::GridEntity getByName dom-38]
  set _DM(52) [pw::GridEntity getByName dom-57]
  set _DM(53) [pw::GridEntity getByName dom-59]
  pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 1 0} {0 0 0}]] -10.26202677] [$_TMP(mode_1) getEntities]
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Rotate

# Rotating
set _DM(1) [pw::GridEntity getByName dom-162]
set _DM(2) [pw::GridEntity getByName dom-163]
set _DM(3) [pw::GridEntity getByName dom-161]
set _DM(4) [pw::GridEntity getByName dom-114]
set _DM(5) [pw::GridEntity getByName dom-109]
set _DM(6) [pw::GridEntity getByName dom-115]
set _DM(7) [pw::GridEntity getByName dom-116]
set _DM(8) [pw::GridEntity getByName dom-144]
set _DM(9) [pw::GridEntity getByName dom-145]
set _DM(10) [pw::GridEntity getByName dom-142]
set _DM(11) [pw::GridEntity getByName dom-143]
set _DM(12) [pw::GridEntity getByName dom-19]
set _DM(13) [pw::GridEntity getByName dom-113]
set _DM(14) [pw::GridEntity getByName dom-110]
set _DM(15) [pw::GridEntity getByName dom-13]
set _DM(16) [pw::GridEntity getByName dom-18]
set _DM(17) [pw::GridEntity getByName dom-112]
set _DM(18) [pw::GridEntity getByName dom-20]
set _DM(19) [pw::GridEntity getByName dom-111]
set _DM(20) [pw::GridEntity getByName dom-81]
set _DM(21) [pw::GridEntity getByName dom-78]
set _DM(22) [pw::GridEntity getByName dom-79]
set _DM(23) [pw::GridEntity getByName dom-80]
set _DM(24) [pw::GridEntity getByName dom-147]
set _DM(25) [pw::GridEntity getByName dom-148]
set _DM(26) [pw::GridEntity getByName dom-146]
set _DM(27) [pw::GridEntity getByName dom-141]
set _DM(28) [pw::GridEntity getByName dom-165]
set _DM(29) [pw::GridEntity getByName dom-164]
set _DM(30) [pw::GridEntity getByName dom-14]
set _DM(31) [pw::GridEntity getByName dom-17]
set _DM(32) [pw::GridEntity getByName dom-15]
set _DM(33) [pw::GridEntity getByName dom-16]
set _DM(34) [pw::GridEntity getByName dom-82]
set _DM(35) [pw::GridEntity getByName dom-84]
set _DM(36) [pw::GridEntity getByName dom-77]
set _DM(37) [pw::GridEntity getByName dom-83]
set _DM(38) [pw::GridEntity getByName dom-49]
set _DM(39) [pw::GridEntity getByName dom-50]
set _DM(40) [pw::GridEntity getByName dom-52]
set _DM(41) [pw::GridEntity getByName dom-47]
set _DM(42) [pw::GridEntity getByName dom-46]
set _DM(43) [pw::GridEntity getByName dom-48]
set _DM(44) [pw::GridEntity getByName dom-51]
set _DM(45) [pw::GridEntity getByName dom-45]
set _BL(1) [pw::GridEntity getByName blk-5]
set _BL(2) [pw::GridEntity getByName blk-3]
set _BL(3) [pw::GridEntity getByName blk-4]
set _BL(4) [pw::GridEntity getByName blk-2]
set _BL(5) [pw::GridEntity getByName blk-1]
set _TMP(mode_1) [pw::Application begin Modify [list $_DM(2) $_DM(3) $_DM(1) $_BL(1) $_DM(30) $_DM(31) $_DM(32) $_DM(12) $_DM(4) $_DM(13) $_DM(14) $_DM(15) $_BL(2) $_DM(16) $_DM(5) $_DM(17) $_DM(18) $_DM(33) $_DM(6) $_DM(7) $_DM(19) $_BL(3) $_BL(4) $_BL(5) $_DM(34) $_DM(20) $_DM(35) $_DM(21) $_DM(22) $_DM(36) $_DM(23) $_DM(37) $_DM(8) $_DM(24) $_DM(9) $_DM(25) $_DM(26) $_DM(10) $_DM(27) $_DM(11) $_DM(38) $_DM(39) $_DM(40) $_DM(41) $_DM(42) $_DM(43) $_DM(44) $_DM(45) $_DM(28) $_DM(29)]]
  pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 1 0} {0 0 0}]] -90] [$_TMP(mode_1) getEntities]
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Rotate

set _TMP(mode_1) [pw::Application begin Modify [list $_DM(2) $_DM(3) $_DM(1) $_BL(1) $_DM(30) $_DM(31) $_DM(32) $_DM(12) $_DM(4) $_DM(13) $_DM(14) $_DM(15) $_BL(2) $_DM(16) $_DM(5) $_DM(17) $_DM(18) $_DM(33) $_DM(6) $_DM(7) $_DM(19) $_BL(3) $_BL(4) $_BL(5) $_DM(34) $_DM(20) $_DM(35) $_DM(21) $_DM(22) $_DM(36) $_DM(23) $_DM(37) $_DM(8) $_DM(24) $_DM(9) $_DM(25) $_DM(26) $_DM(10) $_DM(27) $_DM(11) $_DM(38) $_DM(39) $_DM(40) $_DM(41) $_DM(42) $_DM(43) $_DM(44) $_DM(45) $_DM(28) $_DM(29)]]
  set _DM(46) [pw::GridEntity getByName dom-154]
  set _DM(47) [pw::GridEntity getByName dom-89]
  set _DM(48) [pw::GridEntity getByName dom-21]
$_TMP(mode_1) abort
unset _TMP(mode_1)
set _TMP(mode_1) [pw::Application begin Modify [list $_DM(2) $_DM(3) $_DM(1) $_BL(1) $_DM(30) $_DM(31) $_DM(32) $_DM(12) $_DM(4) $_DM(13) $_DM(14) $_DM(15) $_BL(2) $_DM(16) $_DM(5) $_DM(17) $_DM(18) $_DM(33) $_DM(6) $_DM(7) $_DM(19) $_BL(3) $_BL(4) $_BL(5) $_DM(34) $_DM(20) $_DM(35) $_DM(21) $_DM(22) $_DM(36) $_DM(23) $_DM(37) $_DM(8) $_DM(24) $_DM(9) $_DM(25) $_DM(26) $_DM(10) $_DM(27) $_DM(11) $_DM(38) $_DM(39) $_DM(40) $_DM(41) $_DM(42) $_DM(43) $_DM(44) $_DM(45) $_DM(28) $_DM(29)]]
  set _DM(49) [pw::GridEntity getByName dom-123]
  set _DM(50) [pw::GridEntity getByName dom-12]
  set _DM(51) [pw::GridEntity getByName dom-38]
  set _DM(52) [pw::GridEntity getByName dom-57]
  set _DM(53) [pw::GridEntity getByName dom-59]
  pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 1 0} {0 0 0}]] -10.26202677] [$_TMP(mode_1) getEntities]
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Rotate

set _TMP(mode_1) [pw::Application begin Create]
  set _DM(1) [pw::GridEntity getByName dom-121]
  set _DM(2) [pw::GridEntity getByName dom-101]
  set _DM(3) [pw::GridEntity getByName dom-152]
  set _TMP(PW_1) [pw::SegmentSpline create]
  set _DM(4) [pw::GridEntity getByName dom-102]
  set _DM(5) [pw::GridEntity getByName dom-122]
  set _DM(6) [pw::GridEntity getByName dom-126]
  set _DM(7) [pw::GridEntity getByName dom-123]
  set _DM(8) [pw::GridEntity getByName dom-103]
  set _DM(9) [pw::GridEntity getByName dom-106]
  set _DM(10) [pw::GridEntity getByName dom-161]
  set _DM(11) [pw::GridEntity getByName dom-111]
  set _CN(1) [pw::GridEntity getByName con-78-split-2-split-1]
  set _DM(12) [pw::GridEntity getByName dom-164]
  set _DM(13) [pw::GridEntity getByName dom-162]
  set _CN(2) [pw::GridEntity getByName con-290]
  set _CN(3) [pw::GridEntity getByName con-78-split-2-split-5]
  set _DM(14) [pw::GridEntity getByName dom-115]
  set _DM(15) [pw::GridEntity getByName dom-145]
  set _CN(4) [pw::GridEntity getByName con-259]
  set _DM(16) [pw::GridEntity getByName dom-144]
  set _DM(17) [pw::GridEntity getByName dom-157]
  set _CN(5) [pw::GridEntity getByName con-256]
  set _CN(6) [pw::GridEntity getByName con-257]
  set _CN(7) [pw::GridEntity getByName con-278]
  set _DM(18) [pw::GridEntity getByName dom-137]
  set _DM(19) [pw::GridEntity getByName dom-132]
  set _DM(20) [pw::GridEntity getByName dom-146]
  set _DM(21) [pw::GridEntity getByName dom-140]
  set _DM(22) [pw::GridEntity getByName dom-160]
  set _DM(23) [pw::GridEntity getByName dom-163]
  set _DM(24) [pw::GridEntity getByName dom-158]
  set _DM(25) [pw::GridEntity getByName dom-147]
  set _DM(26) [pw::GridEntity getByName dom-138]
  set _DM(27) [pw::GridEntity getByName dom-155]
  set _DM(28) [pw::GridEntity getByName dom-135]
  set _DM(29) [pw::GridEntity getByName dom-117]
  set _DM(30) [pw::GridEntity getByName dom-156]
  set _DM(31) [pw::GridEntity getByName dom-136]
  set _DM(32) [pw::GridEntity getByName dom-139]
  set _DM(33) [pw::GridEntity getByName dom-159]
  set _DM(34) [pw::GridEntity getByName dom-150]
  set _DM(35) [pw::GridEntity getByName dom-97]
  set _DM(36) [pw::GridEntity getByName dom-143]
  set _DM(37) [pw::GridEntity getByName dom-93]
  set _DM(38) [pw::GridEntity getByName dom-80]
  set _DM(39) [pw::GridEntity getByName dom-79]
  set _DM(40) [pw::GridEntity getByName dom-88]
  set _DM(41) [pw::GridEntity getByName dom-71]
  set _DM(42) [pw::GridEntity getByName dom-91]
  set _DM(43) [pw::GridEntity getByName dom-149]
  set _DM(44) [pw::GridEntity getByName dom-154]
  set _DM(45) [pw::GridEntity getByName dom-153]
  set _DM(46) [pw::GridEntity getByName dom-133]
  set _DM(47) [pw::GridEntity getByName dom-134]
  $_TMP(PW_1) delete
  unset _TMP(PW_1)
$_TMP(mode_1) abort
unset _TMP(mode_1)
set _CN(8) [pw::GridEntity getByName con-78-split-2-split-4]
set _DM(48) [pw::GridEntity getByName dom-130]
set _DM(49) [pw::GridEntity getByName dom-129]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(8) getParameter -arc 0.5]
set _TMP(PW_1) [$_CN(8) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)
pw::Application markUndoLevel Split

set _TMP(mode_1) [pw::Application begin Create]
  set _TMP(PW_1) [pw::SegmentSpline create]
  set _DM(50) [pw::GridEntity getByName dom-68]
  set _DM(51) [pw::GridEntity getByName dom-73]
  set _DM(52) [pw::GridEntity getByName dom-76]
  set _DM(53) [pw::GridEntity getByName dom-96]
  set _CN(9) [pw::GridEntity getByName con-78-split-2-split-4-split-1]
  set _CN(10) [pw::GridEntity getByName con-78-split-2-split-4-split-2]
  set _DM(54) [pw::GridEntity getByName dom-74]
  $_TMP(PW_1) addPoint [$_CN(1) getPosition -arc 0]
  $_TMP(PW_1) addPoint [$_CN(9) getPosition -arc 1]
  set _CN(11) [pw::Connector create]
  $_CN(11) addSegment $_TMP(PW_1)
  unset _TMP(PW_1)
  $_CN(11) calculateDimension
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel {Create 2 Point Connector}

set _TMP(mode_1) [pw::Application begin Create]
  set _TMP(PW_1) [pw::SegmentSpline create]
  $_TMP(PW_1) delete
  unset _TMP(PW_1)
$_TMP(mode_1) abort
unset _TMP(mode_1)
set _TMP(split_params) [list]
lappend _TMP(split_params) 0.5
set _TMP(PW_1) [$_CN(11) split $_TMP(split_params)]
unset _TMP(PW_1)
pw::Application markUndoLevel {Split Into Pieces}

set _CN(12) [pw::GridEntity getByName con-338-split-2]
pw::Entity delete [list $_CN(12)]
pw::Application markUndoLevel Delete

set _TMP(PW_1) [pw::Connector join -reject _TMP(ignored) -keepDistribution [list $_CN(10) $_CN(9)]]
unset _TMP(ignored)
unset _TMP(PW_1)
pw::Application markUndoLevel Join

set _CN(13) [pw::GridEntity getByName con-80-split-1-split-4]
set _DM(55) [pw::GridEntity getByName dom-165]
set _DM(56) [pw::GridEntity getByName dom-94]
set _DM(57) [pw::GridEntity getByName dom-89]
set _DM(58) [pw::GridEntity getByName dom-64]
set _DM(59) [pw::GridEntity getByName dom-44]
set _DM(60) [pw::GridEntity getByName dom-41]
set _DM(61) [pw::GridEntity getByName dom-61]
set _DM(62) [pw::GridEntity getByName dom-90]
set _DM(63) [pw::GridEntity getByName dom-70]
set _DM(64) [pw::GridEntity getByName dom-69]
set _DM(65) [pw::GridEntity getByName dom-42]
set _DM(66) [pw::GridEntity getByName dom-39]
set _DM(67) [pw::GridEntity getByName dom-59]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(13) getParameter -arc 0.5]
set _TMP(PW_1) [$_CN(13) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)
pw::Application markUndoLevel Split

set _TMP(mode_1) [pw::Application begin Create]
  set _DM(68) [pw::GridEntity getByName dom-32]
  set _DM(69) [pw::GridEntity getByName dom-24]
  set _DM(70) [pw::GridEntity getByName dom-12]
  set _DM(71) [pw::GridEntity getByName dom-9]
  set _DM(72) [pw::GridEntity getByName dom-29]
  set _DM(73) [pw::GridEntity getByName dom-58]
  set _DM(74) [pw::GridEntity getByName dom-38]
  set _DM(75) [pw::GridEntity getByName dom-37]
  set _DM(76) [pw::GridEntity getByName dom-57]
  set _TMP(PW_1) [pw::SegmentSpline create]
  set _DM(77) [pw::GridEntity getByName dom-4]
  set _DM(78) [pw::GridEntity getByName dom-62]
  set _CN(14) [pw::GridEntity getByName con-289]
  set _CN(15) [pw::GridEntity getByName con-80-split-1-split-2]
  set _CN(16) [pw::GridEntity getByName con-80-split-1-split-5]
  set _DM(79) [pw::GridEntity getByName dom-142]
  set _CN(17) [pw::GridEntity getByName con-80-split-1-split-4-split-1]
  set _CN(18) [pw::GridEntity getByName con-80-split-1-split-4-split-2]
  $_TMP(PW_1) addPoint [$_CN(14) getPosition -arc 1]
  $_TMP(PW_1) addPoint [$_CN(17) getPosition -arc 1]
  set _CN(19) [pw::Connector create]
  $_CN(19) addSegment $_TMP(PW_1)
  unset _TMP(PW_1)
  $_CN(19) calculateDimension
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel {Create 2 Point Connector}

set _TMP(mode_1) [pw::Application begin Create]
  set _TMP(PW_1) [pw::SegmentSpline create]
  set _DM(80) [pw::GridEntity getByName dom-56]
  set _DM(81) [pw::GridEntity getByName dom-85]
  $_TMP(PW_1) delete
  unset _TMP(PW_1)
$_TMP(mode_1) abort
unset _TMP(mode_1)
set _TMP(split_params) [list]
lappend _TMP(split_params) 0.5
set _TMP(PW_1) [$_CN(19) split $_TMP(split_params)]
unset _TMP(PW_1)
pw::Application markUndoLevel {Split Into Pieces}

set _CN(20) [pw::GridEntity getByName con-338-split-3]
pw::Entity delete [list $_CN(20)]
pw::Application markUndoLevel Delete

set _TMP(PW_1) [pw::Connector join -reject _TMP(ignored) -keepDistribution [list $_CN(17) $_CN(18)]]
unset _TMP(ignored)
unset _TMP(PW_1)
pw::Application markUndoLevel Join

pw::Application clearClipboard
set _CN(1) [pw::GridEntity getByName con-80-split-1-split-4-split-1]
set _CN(2) [pw::GridEntity getByName con-80-split-1-split-2]
set _CN(3) [pw::GridEntity getByName con-80-split-1-split-3]
set _CN(4) [pw::GridEntity getByName con-80-split-1-split-5]
set _CN(5) [pw::GridEntity getByName con-80-split-1-split-6]
pw::Application setClipboard [list $_CN(1) $_CN(2) $_CN(3) $_CN(4) $_CN(5)]
pw::Application markUndoLevel Copy

set _TMP(mode_1) [pw::Application begin Paste]
  set _TMP(PW_1) [$_TMP(mode_1) getEntities]
  set _TMP(mode_2) [pw::Application begin Modify $_TMP(PW_1)]
    set _DM(1) [pw::GridEntity getByName dom-164]
    set _DM(2) [pw::GridEntity getByName dom-162]
    set _DM(3) [pw::GridEntity getByName dom-10]
    set _DM(4) [pw::GridEntity getByName dom-6]
    set _DM(5) [pw::GridEntity getByName dom-25]
    set _DM(6) [pw::GridEntity getByName dom-27]
    set _DM(7) [pw::GridEntity getByName dom-14]
    set _DM(8) [pw::GridEntity getByName dom-26]
    set _DM(9) [pw::GridEntity getByName dom-7]
    set _DM(10) [pw::GridEntity getByName dom-30]
    set _DM(11) [pw::GridEntity getByName dom-161]
    set _DM(12) [pw::GridEntity getByName dom-163]
    set _DM(13) [pw::GridEntity getByName dom-147]
    set _DM(14) [pw::GridEntity getByName dom-138]
    set _DM(15) [pw::GridEntity getByName dom-158]
    set _DM(16) [pw::GridEntity getByName dom-154]
    set _DM(17) [pw::GridEntity getByName dom-134]
    set _DM(18) [pw::GridEntity getByName dom-133]
    set _DM(19) [pw::GridEntity getByName dom-153]
    set _DM(20) [pw::GridEntity getByName dom-88]
    set _DM(21) [pw::GridEntity getByName dom-76]
    set _DM(22) [pw::GridEntity getByName dom-68]
    set _DM(23) [pw::GridEntity getByName dom-73]
    set _DM(24) [pw::GridEntity getByName dom-92]
    set _DM(25) [pw::GridEntity getByName dom-93]
    set _DM(26) [pw::GridEntity getByName dom-96]
    set _DM(27) [pw::GridEntity getByName dom-75]
    set _DM(28) [pw::GridEntity getByName dom-67]
    set _DM(29) [pw::GridEntity getByName dom-72]
    set _DM(30) [pw::GridEntity getByName dom-87]
    set _DM(31) [pw::GridEntity getByName dom-95]
    set _CN(6) [pw::GridEntity getByName con-338-split-2]
    set _DM(32) [pw::GridEntity getByName dom-149]
    set _DM(33) [pw::GridEntity getByName dom-129]
    set _DM(34) [pw::GridEntity getByName dom-32]
    set _DM(35) [pw::GridEntity getByName dom-18]
    set _DM(36) [pw::GridEntity getByName dom-12]
    set _DM(37) [pw::GridEntity getByName dom-51]
    set _DM(38) [pw::GridEntity getByName dom-62]
    set _DM(39) [pw::GridEntity getByName dom-58]
    set _DM(40) [pw::GridEntity getByName dom-38]
    set _DM(41) [pw::GridEntity getByName dom-165]
    set _DM(42) [pw::GridEntity getByName dom-5]
    set _DM(43) [pw::GridEntity getByName dom-37]
    set _DM(44) [pw::GridEntity getByName dom-57]
    set _DM(45) [pw::GridEntity getByName dom-33]
    set _DM(46) [pw::GridEntity getByName dom-53]
    set _DM(47) [pw::GridEntity getByName dom-79]
    set _DM(48) [pw::GridEntity getByName dom-91]
    set _DM(49) [pw::GridEntity getByName dom-80]
    set _DM(50) [pw::GridEntity getByName dom-15]
    set _DM(51) [pw::GridEntity getByName dom-21]
    set _CN(7) [pw::GridEntity getByName con-298]
    set _DM(52) [pw::GridEntity getByName dom-148]
    set _CN(8) [pw::GridEntity getByName con-67]
    set _DM(53) [pw::GridEntity getByName dom-31]
    set _CN(9) [pw::GridEntity getByName con-68]
    set _CN(10) [pw::GridEntity getByName con-75]
    set _DM(54) [pw::GridEntity getByName dom-46]
    pw::Entity transform [pwu::Transform scaling -anchor [$_CN(6) getPosition -arc 1] {5.9349868140000002 5.9349868140000002 5.9349868140000002}] [$_TMP(mode_2) getEntities]
  $_TMP(mode_2) end
  unset _TMP(mode_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Paste

unset _TMP(PW_1)
pw::Application clearClipboard
set _CN(11) [pw::GridEntity getByName con-78-split-2-split-4-split-1]
set _CN(12) [pw::GridEntity getByName con-78-split-2-split-1]
set _CN(13) [pw::GridEntity getByName con-78-split-2-split-3]
set _CN(14) [pw::GridEntity getByName con-78-split-2-split-5]
set _CN(15) [pw::GridEntity getByName con-78-split-2-split-6]
pw::Application setClipboard [list $_CN(11) $_CN(12) $_CN(13) $_CN(14) $_CN(15)]
pw::Application markUndoLevel Copy

set _TMP(mode_1) [pw::Application begin Paste]
  set _TMP(PW_1) [$_TMP(mode_1) getEntities]
  set _TMP(mode_2) [pw::Application begin Modify $_TMP(PW_1)]
    set _CN(16) [pw::GridEntity getByName con-133]
    set _CN(17) [pw::GridEntity getByName con-8-split-7]
    set _CN(18) [pw::GridEntity getByName con-6-split-1-split-5]
    set _DM(55) [pw::GridEntity getByName dom-65]
    set _DM(56) [pw::GridEntity getByName dom-69]
    set _DM(57) [pw::GridEntity getByName dom-77]
    set _DM(58) [pw::GridEntity getByName dom-78]
    set _CN(19) [pw::GridEntity getByName con-145]
    set _DM(59) [pw::GridEntity getByName dom-71]
    set _CN(20) [pw::GridEntity getByName con-8-split-8]
    set _CN(21) [pw::GridEntity getByName con-138]
    set _CN(22) [pw::GridEntity getByName con-148]
    set _DM(60) [pw::GridEntity getByName dom-85]
    set _DM(61) [pw::GridEntity getByName dom-42]
    set _CN(23) [pw::GridEntity getByName con-156]
    set _DM(62) [pw::GridEntity getByName dom-82]
    set _DM(63) [pw::GridEntity getByName dom-83]
    set _DM(64) [pw::GridEntity getByName dom-94]
    set _CN(24) [pw::GridEntity getByName con-157]
    set _CN(25) [pw::GridEntity getByName con-159]
    set _CN(26) [pw::GridEntity getByName con-183]
    set _DM(65) [pw::GridEntity getByName dom-74]
    set _DM(66) [pw::GridEntity getByName dom-39]
    set _CN(27) [pw::GridEntity getByName con-8-split-4]
    set _DM(67) [pw::GridEntity getByName dom-47]
    set _CN(28) [pw::GridEntity getByName con-8-split-5]
    set _CN(29) [pw::GridEntity getByName con-86]
    set _CN(30) [pw::GridEntity getByName con-96]
    set _DM(68) [pw::GridEntity getByName dom-142]
    set _CN(31) [pw::GridEntity getByName con-338-split-1]
    set _CN(32) [pw::GridEntity getByName con-250]
    set _DM(69) [pw::GridEntity getByName dom-141]
    set _CN(33) [pw::GridEntity getByName con-249]
    set _CN(34) [pw::GridEntity getByName con-253]
    set _CN(35) [pw::GridEntity getByName con-265]
    set _CN(36) [pw::GridEntity getByName con-303]
    pw::Entity transform [pwu::Transform scaling -anchor [$_CN(31) getPosition -arc 1] {5.9349868140000002 5.9349868140000002 5.9349868140000002}] [$_TMP(mode_2) getEntities]
  $_TMP(mode_2) end
  unset _TMP(mode_2)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Paste

unset _TMP(PW_1)

set _CN(1) [pw::GridEntity getByName con-78-split-2-split-10]
set _CN(2) [pw::GridEntity getByName con-78-split-2-split-9]
set _CN(3) [pw::GridEntity getByName con-78-split-2-split-8]
set _CN(4) [pw::GridEntity getByName con-78-split-2-split-7]
set _CN(5) [pw::GridEntity getByName con-78-split-2-split-4-split-2]
set _CN(6) [pw::GridEntity getByName con-80-split-1-split-7]
set _CN(7) [pw::GridEntity getByName con-80-split-1-split-9]
set _CN(8) [pw::GridEntity getByName con-80-split-1-split-8]
set _CN(9) [pw::GridEntity getByName con-80-split-1-split-4-split-2]
set _CN(10) [pw::GridEntity getByName con-80-split-1-split-10]
set _TMP(PW_1) [pw::Connector join -reject _TMP(ignored) -keepDistribution [list $_CN(1) $_CN(2) $_CN(3) $_CN(4) $_CN(5) $_CN(7) $_CN(9) $_CN(10) $_CN(6) $_CN(8)]]
unset _TMP(ignored)
unset _TMP(PW_1)
pw::Application markUndoLevel Join

set _CN(11) [pw::GridEntity getByName con-80-split-1-split-4-split-2]
set _CN(12) [pw::GridEntity getByName con-78-split-2-split-4-split-2]
set _TMP(mode_1) [pw::Application begin Modify [list $_CN(11) $_CN(12)]]
  $_CN(11) removeAllBreakPoints
  $_CN(12) removeAllBreakPoints
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Distribute

set _TMP(PW_1) [pw::Collection create]
$_TMP(PW_1) set [list $_CN(11) $_CN(12)]
$_TMP(PW_1) do setDimensionFromSpacing -resetDistribution 0.0030000000000000001
$_TMP(PW_1) delete
unset _TMP(PW_1)
pw::CutPlane refresh
pw::Application markUndoLevel Dimension

set _DM(1) [pw::GridEntity getByName dom-63]
set _DM(2) [pw::GridEntity getByName dom-54]
set _DM(3) [pw::GridEntity getByName dom-60]
set _DM(4) [pw::GridEntity getByName dom-34]
set _DM(5) [pw::GridEntity getByName dom-40]
set _DM(6) [pw::GridEntity getByName dom-43]
set _DM(7) [pw::GridEntity getByName dom-64]
set _CN(13) [pw::GridEntity getByName con-15-split-6]
set _CN(14) [pw::GridEntity getByName con-7-split-1-split-2-split-3]
set _CN(15) [pw::GridEntity getByName con-15-split-5]
set _CN(16) [pw::GridEntity getByName con-118]
set _DM(8) [pw::GridEntity getByName dom-35]
set _DM(9) [pw::GridEntity getByName dom-36]
set _DM(10) [pw::GridEntity getByName dom-41]
set _CN(17) [pw::GridEntity getByName con-6-split-2-split-2-split-3]
set _CN(18) [pw::GridEntity getByName con-6-split-2-split-2-split-4]
set _CN(19) [pw::GridEntity getByName con-90]
set _CN(20) [pw::GridEntity getByName con-92]
set _CN(21) [pw::GridEntity getByName con-7-split-1-split-2-split-4]
set _DM(11) [pw::GridEntity getByName dom-44]
set _CN(22) [pw::GridEntity getByName con-119]
set _DM(12) [pw::GridEntity getByName dom-55]
set _DM(13) [pw::GridEntity getByName dom-56]
set _DM(14) [pw::GridEntity getByName dom-61]
set _CN(23) [pw::GridEntity getByName con-120]
set _CN(24) [pw::GridEntity getByName con-122]
set _CN(25) [pw::GridEntity getByName con-129]
set _DM(15) [pw::GridEntity getByName dom-57]
set _DM(16) [pw::GridEntity getByName dom-37]
set _DM(17) [pw::GridEntity getByName dom-38]
set _DM(18) [pw::GridEntity getByName dom-58]
set _CN(26) [pw::GridEntity getByName con-85]
set _CN(27) [pw::GridEntity getByName con-87]
set _CN(28) [pw::GridEntity getByName con-125]
set _CN(29) [pw::GridEntity getByName con-86]
set _CN(30) [pw::GridEntity getByName con-15-split-7]
set _DM(19) [pw::GridEntity getByName dom-39]
set _CN(31) [pw::GridEntity getByName con-19-split-3]
set _DM(20) [pw::GridEntity getByName dom-42]
set _CN(32) [pw::GridEntity getByName con-88]
set _DM(21) [pw::GridEntity getByName dom-62]
set _CN(33) [pw::GridEntity getByName con-126]
set _CN(34) [pw::GridEntity getByName con-130]
set _DM(22) [pw::GridEntity getByName dom-59]
set _DM(23) [pw::GridEntity getByName dom-89]
set _DM(24) [pw::GridEntity getByName dom-69]
set _DM(25) [pw::GridEntity getByName dom-70]
set _DM(26) [pw::GridEntity getByName dom-90]
set _DM(27) [pw::GridEntity getByName dom-74]
set _DM(28) [pw::GridEntity getByName dom-94]
set _DM(29) [pw::GridEntity getByName dom-91]
set _DM(30) [pw::GridEntity getByName dom-71]
set _DM(31) [pw::GridEntity getByName dom-76]
set _DM(32) [pw::GridEntity getByName dom-96]
set _DM(33) [pw::GridEntity getByName dom-73]
set _DM(34) [pw::GridEntity getByName dom-68]
set _DM(35) [pw::GridEntity getByName dom-88]
set _DM(36) [pw::GridEntity getByName dom-93]
set _DM(37) [pw::GridEntity getByName dom-153]
set _DM(38) [pw::GridEntity getByName dom-149]
set _DM(39) [pw::GridEntity getByName dom-129]
set _DM(40) [pw::GridEntity getByName dom-133]
set _DM(41) [pw::GridEntity getByName dom-134]
set _DM(42) [pw::GridEntity getByName dom-154]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(11) getParameter -closest [pw::Application getXYZ [$_CN(11) closestPoint [$_CN(12) getPosition -arc 0]]]]
set _TMP(PW_1) [$_CN(11) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)
pw::Application markUndoLevel Split

set _CN(35) [pw::GridEntity getByName con-80-split-1-split-4-split-2-split-2]
set _CN(36) [pw::GridEntity getByName con-80-split-1-split-4-split-2-split-1]
set _DM(43) [pw::GridEntity getByName dom-86]
set _TMP(split_params) [list]
lappend _TMP(split_params) [$_CN(12) getParameter -closest [pw::Application getXYZ [$_CN(12) closestPoint [$_CN(36) getPosition -arc 0]]]]
set _TMP(PW_1) [$_CN(12) split $_TMP(split_params)]
unset _TMP(PW_1)
unset _TMP(split_params)
pw::Application markUndoLevel Split

set _TMP(mode_1) [pw::Application begin Create]
  set _DM(44) [pw::GridEntity getByName dom-92]
  set _DM(45) [pw::GridEntity getByName dom-72]
  set _DM(46) [pw::GridEntity getByName dom-75]
  set _DM(47) [pw::GridEntity getByName dom-95]
  set _TMP(PW_1) [pw::SegmentSpline create]
  set _CN(37) [pw::GridEntity getByName con-78-split-2-split-4-split-2-split-1]
  set _CN(38) [pw::GridEntity getByName con-78-split-2-split-4-split-2-split-2]
  set _DM(48) [pw::GridEntity getByName dom-85]
  set _DM(49) [pw::GridEntity getByName dom-65]
  $_TMP(PW_1) addPoint [$_CN(37) getPosition -arc 0]
  $_TMP(PW_1) addPoint [$_CN(36) getPosition -arc 1]
  set _CN(39) [pw::Connector create]
  $_CN(39) addSegment $_TMP(PW_1)
  unset _TMP(PW_1)
  $_CN(39) calculateDimension
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel {Create 2 Point Connector}

set _TMP(mode_1) [pw::Application begin Create]
  set _TMP(PW_1) [pw::SegmentSpline create]
  $_TMP(PW_1) addPoint [$_CN(36) getPosition -arc 0]
  $_TMP(PW_1) addPoint [$_CN(37) getPosition -arc 1]
  set _CN(40) [pw::Connector create]
  $_CN(40) addSegment $_TMP(PW_1)
  unset _TMP(PW_1)
  $_CN(40) calculateDimension
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel {Create 2 Point Connector}

set _TMP(mode_1) [pw::Application begin Create]
  set _TMP(PW_1) [pw::SegmentSpline create]
  set _DM(50) [pw::GridEntity getByName dom-164]
  set _DM(51) [pw::GridEntity getByName dom-162]
  set _DM(52) [pw::GridEntity getByName dom-51]
  set _DM(53) [pw::GridEntity getByName dom-165]
  set _DM(54) [pw::GridEntity getByName dom-163]
  set _DM(55) [pw::GridEntity getByName dom-47]
  set _CN(41) [pw::GridEntity getByName con-12-split-8]
  set _DM(56) [pw::GridEntity getByName dom-83]
  set _DM(57) [pw::GridEntity getByName dom-84]
  set _CN(42) [pw::GridEntity getByName con-12-split-9]
  set _CN(43) [pw::GridEntity getByName con-139]
  set _CN(44) [pw::GridEntity getByName con-158]
  set _DM(58) [pw::GridEntity getByName dom-158]
  set _DM(59) [pw::GridEntity getByName dom-147]
  set _DM(60) [pw::GridEntity getByName dom-160]
  set _CN(45) [pw::GridEntity getByName con-171]
  set _CN(46) [pw::GridEntity getByName con-15-split-9]
  set _CN(47) [pw::GridEntity getByName con-7-split-1-split-2-split-5]
  set _CN(48) [pw::GridEntity getByName con-15-split-8]
  set _CN(49) [pw::GridEntity getByName con-170]
  set _DM(61) [pw::GridEntity getByName dom-87]
  set _CN(50) [pw::GridEntity getByName con-172]
  set _CN(51) [pw::GridEntity getByName con-174]
  set _CN(52) [pw::GridEntity getByName con-181]
  set _DM(62) [pw::GridEntity getByName dom-67]
  set _CN(53) [pw::GridEntity getByName con-6-split-2-split-2-split-5]
  set _CN(54) [pw::GridEntity getByName con-6-split-2-split-2-split-6]
  set _CN(55) [pw::GridEntity getByName con-142]
  set _CN(56) [pw::GridEntity getByName con-7-split-1-split-2-split-6]
  set _CN(57) [pw::GridEntity getByName con-144]
  set _DM(63) [pw::GridEntity getByName dom-66]
  set _CN(58) [pw::GridEntity getByName con-6-split-1-split-6]
  set _CN(59) [pw::GridEntity getByName con-135]
  set _CN(60) [pw::GridEntity getByName con-137]
  set _CN(61) [pw::GridEntity getByName con-6-split-2-split-3]
  set _CN(62) [pw::GridEntity getByName con-7-split-1-split-3]
  set _CN(63) [pw::GridEntity getByName con-140]
  set _CN(64) [pw::GridEntity getByName con-7-split-2-split-5]
  set _CN(65) [pw::GridEntity getByName con-164]
  set _CN(66) [pw::GridEntity getByName con-165]
  $_TMP(PW_1) delete
  unset _TMP(PW_1)
$_TMP(mode_1) abort
unset _TMP(mode_1)
set _TMP(PW_1) [pw::Collection create]
$_TMP(PW_1) set [list $_CN(39) $_CN(40)]
$_TMP(PW_1) do setDimensionFromSpacing -resetDistribution 0.0030000000000000001
$_TMP(PW_1) delete
unset _TMP(PW_1)
pw::CutPlane refresh
pw::Application markUndoLevel Dimension

pw::Application setGridPreference Structured
set _TMP(PW_1) [pw::DomainStructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(39) $_CN(38) $_CN(36) $_CN(40)]]
unset _TMP(unusedCons)
unset _TMP(PW_1)
pw::Application markUndoLevel {Assemble Domains}

set _TMP(PW_1) [pw::DomainStructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(39) $_CN(35) $_CN(37) $_CN(40)]]
unset _TMP(unusedCons)
unset _TMP(PW_1)
pw::Application markUndoLevel {Assemble Domains}

set _TMP(mode_1) [pw::Application begin Create]
  set _DB(1) [pw::Plane create]
  set _DM(1) [pw::GridEntity getByName dom-166]
  set _DM(2) [pw::GridEntity getByName dom-121]
  set _DM(3) [pw::GridEntity getByName dom-101]
  set _DM(4) [pw::GridEntity getByName dom-102]
  set _DM(5) [pw::GridEntity getByName dom-122]
  set _DM(6) [pw::GridEntity getByName dom-123]
  set _DM(7) [pw::GridEntity getByName dom-152]
  set _DM(8) [pw::GridEntity getByName dom-21]
  set _DM(9) [pw::GridEntity getByName dom-103]
  set _DM(10) [pw::GridEntity getByName dom-106]
  set _DM(11) [pw::GridEntity getByName dom-126]
  set _DM(12) [pw::GridEntity getByName dom-25]
  set _DM(13) [pw::GridEntity getByName dom-5]
  set _DM(14) [pw::GridEntity getByName dom-6]
  set _DM(15) [pw::GridEntity getByName dom-26]
  set _DM(16) [pw::GridEntity getByName dom-164]
  set _DM(17) [pw::GridEntity getByName dom-161]
  set _DM(18) [pw::GridEntity getByName dom-14]
  set _DM(19) [pw::GridEntity getByName dom-111]
  set _DM(20) [pw::GridEntity getByName dom-53]
  set _DM(21) [pw::GridEntity getByName dom-58]
  set _DM(22) [pw::GridEntity getByName dom-115]
  set _DM(23) [pw::GridEntity getByName dom-20]
  set _CN(1) [pw::GridEntity getByName con-8-split-1]
  set _DM(24) [pw::GridEntity getByName dom-1]
  set _DM(25) [pw::GridEntity getByName dom-13]
  set _CN(2) [pw::GridEntity getByName con-28]
  set _CN(3) [pw::GridEntity getByName con-5]
  set _CN(4) [pw::GridEntity getByName con-6-split-1-split-1]
  set _CN(5) [pw::GridEntity getByName con-12-split-3]
  set _CN(6) [pw::GridEntity getByName con-44]
  set _CN(7) [pw::GridEntity getByName con-7-split-2-split-2]
  set _CN(8) [pw::GridEntity getByName con-24]
  set _CN(9) [pw::GridEntity getByName con-45]
  set _CN(10) [pw::GridEntity getByName con-52]
  set _DM(26) [pw::GridEntity getByName dom-137]
  set _DM(27) [pw::GridEntity getByName dom-132]
  set _DM(28) [pw::GridEntity getByName dom-140]
  set _DM(29) [pw::GridEntity getByName dom-160]
  set _DM(30) [pw::GridEntity getByName dom-157]
  set _CN(11) [pw::GridEntity getByName con-78-split-2-split-1]
  set _CN(12) [pw::GridEntity getByName con-78-split-2-split-5]
  set _CN(13) [pw::GridEntity getByName con-338-split-1]
  set _CN(14) [pw::GridEntity getByName con-290]
  set _DM(31) [pw::GridEntity getByName dom-110]
  set _DM(32) [pw::GridEntity getByName dom-135]
  set _DM(33) [pw::GridEntity getByName dom-116]
  set _DM(34) [pw::GridEntity getByName dom-155]
  set _DM(35) [pw::GridEntity getByName dom-162]
  set _DM(36) [pw::GridEntity getByName dom-138]
  set _DM(37) [pw::GridEntity getByName dom-158]
  set _DM(38) [pw::GridEntity getByName dom-165]
  set _CN(15) [pw::GridEntity getByName con-337]
  set _CN(16) [pw::GridEntity getByName con-78-split-2-split-6]
  $_DB(1) setPoints [$_CN(11) getPosition -arc 0] [$_CN(13) getPosition -arc 1] [$_CN(15) getPosition -arc 1]
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Planes

set _DM(39) [pw::GridEntity getByName dom-159]
set _DM(40) [pw::GridEntity getByName dom-156]
set _DM(41) [pw::GridEntity getByName dom-136]
set _DM(42) [pw::GridEntity getByName dom-139]
set _DM(43) [pw::GridEntity getByName dom-97]
set _DM(44) [pw::GridEntity getByName dom-117]
set _DM(45) [pw::GridEntity getByName dom-151]
set _DM(46) [pw::GridEntity getByName dom-27]
set _DM(47) [pw::GridEntity getByName dom-7]
set _DM(48) [pw::GridEntity getByName dom-10]
set _DM(49) [pw::GridEntity getByName dom-30]
set _DM(50) [pw::GridEntity getByName dom-125]
set _DM(51) [pw::GridEntity getByName dom-33]
set _DM(52) [pw::GridEntity getByName dom-105]
set _DM(53) [pw::GridEntity getByName dom-108]
set _DM(54) [pw::GridEntity getByName dom-128]
set _DM(55) [pw::GridEntity getByName dom-57]
set _DM(56) [pw::GridEntity getByName dom-100]
set _DM(57) [pw::GridEntity getByName dom-120]
set _DM(58) [pw::GridEntity getByName dom-38]
set _DM(59) [pw::GridEntity getByName dom-37]
set _DM(60) [pw::GridEntity getByName dom-12]
set _DM(61) [pw::GridEntity getByName dom-32]
set _DM(62) [pw::GridEntity getByName dom-29]
set _DM(63) [pw::GridEntity getByName dom-9]
set _DM(64) [pw::GridEntity getByName dom-24]
set _TMP(mode_1) [pw::Application begin Create]
  set _CN(17) [pw::GridEntity getByName con-78-split-2-split-3]
  set _CN(18) [pw::GridEntity getByName con-78-split-2-split-4-split-1]
  set _TMP(PW_1) [pw::Edge createFromConnectors [list $_CN(16) $_CN(12) $_CN(11) $_CN(17) $_CN(18)]]
  set _TMP(edge_1) [lindex $_TMP(PW_1) 0]
  unset _TMP(PW_1)
  set _DM(65) [pw::DomainStructured create]
  $_DM(65) addEdge $_TMP(edge_1)
$_TMP(mode_1) end
unset _TMP(mode_1)
set _TMP(mode_1) [pw::Application begin ExtrusionSolver [list $_DM(65)]]
  $_TMP(mode_1) setKeepFailingStep true
  $_DM(65) setExtrusionSolverAttribute NormalMarchingMode Plane
  $_DM(65) setExtrusionSolverAttribute NormalMarchingVector {0.118258810734 0.0555336280034 0.991428701342}
  $_DM(65) setExtrusionSolverAttribute NormalMarchingVector {-0.118258810734 -0.0555336280034 -0.991428701342}
  $_DM(65) setExtrusionSolverAttribute NormalMarchingMode Plane
  $_DM(65) setExtrusionSolverAttribute NormalMarchingVector {-0.350333073973 0.00891722378419 0.936582735481}
  $_DM(65) setExtrusionSolverAttribute NormalMarchingVector {0.350333073973 -0.00891722378419 -0.936582735481}
  $_DM(65) setExtrusionSolverAttribute NormalInitialStepSize 9.29048e-05
  $_DM(65) setExtrusionSolverAttribute SpacingGrowthFactor 1
  $_TMP(mode_1) run 40
$_TMP(mode_1) end
unset _TMP(mode_1)
unset _TMP(edge_1)
pw::Application markUndoLevel {Extrude, Normal}

set _TMP(mode_1) [pw::Application begin Create]
$_TMP(mode_1) abort
unset _TMP(mode_1)
pw::Application setGridPreference Unstructured
set _TMP(mode_1) [pw::Application begin Create]
  set _CN(1) [pw::GridEntity getByName con-78-split-2-split-4-split-2-split-2]
  set _TMP(edge_1) [pw::Edge create]
  $_TMP(edge_1) addConnector $_CN(1)
  set _CN(2) [pw::GridEntity getByName con-78-split-2-split-4-split-2-split-1]
  $_TMP(edge_1) addConnector $_CN(2)
  set _CN(3) [pw::GridEntity getByName con-341]
  set _TMP(edge_2) [pw::Edge create]
  $_TMP(edge_2) addConnector $_CN(3)
  $_TMP(edge_2) reverse
  set _DM(1) [pw::DomainUnstructured create]
  $_DM(1) addEdge $_TMP(edge_1)
  $_DM(1) addEdge $_TMP(edge_2)
  unset _TMP(edge_2)
  unset _TMP(edge_1)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel {Assemble Domain}

set _TMP(mode_1) [pw::Application begin Create]
$_TMP(mode_1) abort
unset _TMP(mode_1)
set _CN(4) [pw::GridEntity getByName con-80-split-1-split-2]
set _CN(5) [pw::GridEntity getByName con-80-split-1-split-3]
set _CN(6) [pw::GridEntity getByName con-80-split-1-split-5]
set _CN(7) [pw::GridEntity getByName con-80-split-1-split-6]
set _CN(8) [pw::GridEntity getByName con-80-split-1-split-4-split-1]
set _TMP(PW_1) [pw::DomainUnstructured createFromConnectors -reject _TMP(unusedCons)  [list $_CN(4) $_CN(5) $_CN(6) $_CN(7) $_CN(8)]]
unset _TMP(unusedCons)
unset _TMP(PW_1)
pw::Application markUndoLevel {Assemble Domains}

set _TMP(mode_1) [pw::Application begin Create]
  set _CN(9) [pw::GridEntity getByName con-80-split-1-split-4-split-2-split-1]
  set _TMP(edge_1) [pw::Edge create]
  $_TMP(edge_1) addConnector $_CN(9)
  $_TMP(edge_1) addConnector $_CN(9)
  set _CN(10) [pw::GridEntity getByName con-80-split-1-split-4-split-2-split-2]
  $_TMP(edge_1) addConnector $_CN(10)
  $_TMP(edge_1) reverse
  set _CN(11) [pw::GridEntity getByName con-339]
  $_TMP(edge_1) addConnector $_CN(11)
  $_TMP(edge_1) reverse
  set _CN(12) [pw::GridEntity getByName con-338]
  $_TMP(edge_1) addConnector $_CN(12)
$_TMP(mode_1) abort
unset _TMP(mode_1)
unset _TMP(edge_1)
set _TMP(mode_1) [pw::Application begin Create]
  set _CN(13) [pw::GridEntity getByName con-131]
  set _TMP(edge_1) [pw::Edge create]
  $_TMP(edge_1) addConnector $_CN(13)
  $_TMP(edge_1) addConnector $_CN(13)
  $_TMP(edge_1) removeLastConnector
  $_TMP(edge_1) removeLastConnector
  $_TMP(edge_1) delete
  unset _TMP(edge_1)
  set _TMP(edge_1) [pw::Edge create]
  $_TMP(edge_1) addConnector $_CN(9)
  $_TMP(edge_1) addConnector $_CN(10)
  set _TMP(edge_2) [pw::Edge create]
  $_TMP(edge_2) addConnector $_CN(7)
  $_TMP(edge_2) addConnector $_CN(6)
  $_TMP(edge_2) addConnector $_CN(4)
  $_TMP(edge_2) addConnector $_CN(5)
  $_TMP(edge_2) addConnector $_CN(8)
  set _DM(2) [pw::DomainUnstructured create]
  $_DM(2) addEdge $_TMP(edge_1)
  $_DM(2) addEdge $_TMP(edge_2)
  unset _TMP(edge_2)
  unset _TMP(edge_1)
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel {Assemble Domain}

set _TMP(mode_1) [pw::Application begin Create]
  set _DM(1) [pw::GridEntity getByName dom-171]
  set _DM(2) [pw::GridEntity getByName dom-170]
  set _TMP(PW_1) [pw::FaceUnstructured createFromDomains [list $_DM(1) $_DM(2)]]
  set _TMP(face_1) [lindex $_TMP(PW_1) 0]
  unset _TMP(PW_1)
  set _BL(1) [pw::BlockExtruded create]
  $_BL(1) addFace $_TMP(face_1)
$_TMP(mode_1) end
unset _TMP(mode_1)
set _TMP(mode_1) [pw::Application begin ExtrusionSolver [list $_BL(1)]]
  $_TMP(mode_1) setKeepFailingStep true
  $_BL(1) setExtrusionSolverAttribute Mode Translate
  $_BL(1) setExtrusionSolverAttribute TranslateDirection {1 0 0}
  set _DM(3) [pw::GridEntity getByName dom-169]
  set _DM(4) [pw::GridEntity getByName dom-166]
  set _DM(5) [pw::GridEntity getByName dom-32]
  set _DM(6) [pw::GridEntity getByName dom-24]
  set _DM(7) [pw::GridEntity getByName dom-27]
  set _DM(8) [pw::GridEntity getByName dom-29]
  set _DM(9) [pw::GridEntity getByName dom-12]
  set _DM(10) [pw::GridEntity getByName dom-9]
  set _DM(11) [pw::GridEntity getByName dom-26]
  set _DM(12) [pw::GridEntity getByName dom-30]
  set _DM(13) [pw::GridEntity getByName dom-1]
  set _DM(14) [pw::GridEntity getByName dom-6]
  set _DM(15) [pw::GridEntity getByName dom-5]
  set _DM(16) [pw::GridEntity getByName dom-21]
  set _DM(17) [pw::GridEntity getByName dom-7]
  set _DM(18) [pw::GridEntity getByName dom-8]
  set _DM(19) [pw::GridEntity getByName dom-10]
  set _DM(20) [pw::GridEntity getByName dom-11]
  set _DM(21) [pw::GridEntity getByName dom-31]
  set _DM(22) [pw::GridEntity getByName dom-28]
  set _DM(23) [pw::GridEntity getByName dom-125]
  set _DM(24) [pw::GridEntity getByName dom-105]
  set _DM(25) [pw::GridEntity getByName dom-108]
  set _DM(26) [pw::GridEntity getByName dom-128]
  set _DM(27) [pw::GridEntity getByName dom-129]
  set _DM(28) [pw::GridEntity getByName dom-133]
  set _DM(29) [pw::GridEntity getByName dom-134]
  set _DM(30) [pw::GridEntity getByName dom-153]
  set _DM(31) [pw::GridEntity getByName dom-149]
  set _DM(32) [pw::GridEntity getByName dom-154]
  set _DM(33) [pw::GridEntity getByName dom-135]
  set _DM(34) [pw::GridEntity getByName dom-138]
  set _DM(35) [pw::GridEntity getByName dom-155]
  set _DM(36) [pw::GridEntity getByName dom-158]
  set _DM(37) [pw::GridEntity getByName dom-168]
  set _DM(38) [pw::GridEntity getByName dom-162]
  set _DM(39) [pw::GridEntity getByName dom-116]
  set _DM(40) [pw::GridEntity getByName dom-122]
  set _DM(41) [pw::GridEntity getByName dom-165]
  set _DM(42) [pw::GridEntity getByName dom-143]
  set _DM(43) [pw::GridEntity getByName dom-140]
  set _DM(44) [pw::GridEntity getByName dom-160]
  set _DM(45) [pw::GridEntity getByName dom-57]
  set _DM(46) [pw::GridEntity getByName dom-46]
  set _DM(47) [pw::GridEntity getByName dom-37]
  set _DM(48) [pw::GridEntity getByName dom-164]
  set _DM(49) [pw::GridEntity getByName dom-42]
  set _DM(50) [pw::GridEntity getByName dom-62]
  set _DM(51) [pw::GridEntity getByName dom-38]
  set _DM(52) [pw::GridEntity getByName dom-58]
  set _DM(53) [pw::GridEntity getByName dom-53]
  set _DM(54) [pw::GridEntity getByName dom-161]
  set _DM(55) [pw::GridEntity getByName dom-33]
  set _DM(56) [pw::GridEntity getByName dom-15]
  set _CN(1) [pw::GridEntity getByName con-259]
  set _DM(57) [pw::GridEntity getByName dom-144]
  set _DM(58) [pw::GridEntity getByName dom-145]
  set _DM(59) [pw::GridEntity getByName dom-152]
  set _DM(60) [pw::GridEntity getByName dom-157]
  set _CN(2) [pw::GridEntity getByName con-256]
  set _CN(3) [pw::GridEntity getByName con-257]
  set _CN(4) [pw::GridEntity getByName con-278]
  set _DM(61) [pw::GridEntity getByName dom-51]
  set _DM(62) [pw::GridEntity getByName dom-137]
  set _DM(63) [pw::GridEntity getByName dom-45]
  set _CN(5) [pw::GridEntity getByName con-338-split-1]
  set _DM(64) [pw::GridEntity getByName dom-117]
  set _DM(65) [pw::GridEntity getByName dom-109]
  set _DM(66) [pw::GridEntity getByName dom-97]
  set _DM(67) [pw::GridEntity getByName dom-102]
  set _DM(68) [pw::GridEntity getByName dom-101]
  set _DM(69) [pw::GridEntity getByName dom-110]
  set _CN(6) [pw::GridEntity getByName con-212]
  set _DM(70) [pw::GridEntity getByName dom-115]
  set _DM(71) [pw::GridEntity getByName dom-126]
  set _CN(7) [pw::GridEntity getByName con-210]
  set _CN(8) [pw::GridEntity getByName con-211]
  set _CN(9) [pw::GridEntity getByName con-229]
  set _CN(10) [pw::GridEntity getByName con-93]
  set _CN(11) [pw::GridEntity getByName con-94]
  set _CN(12) [pw::GridEntity getByName con-97]
  set _CN(13) [pw::GridEntity getByName con-109]
  set _CN(14) [pw::GridEntity getByName con-337]
  set _DM(72) [pw::GridEntity getByName dom-163]
  set _CN(15) [pw::GridEntity getByName con-261]
  set _DM(73) [pw::GridEntity getByName dom-146]
  set _CN(16) [pw::GridEntity getByName con-258]
  set _CN(17) [pw::GridEntity getByName con-277]
  set _CN(18) [pw::GridEntity getByName con-298]
  set _CN(19) [pw::GridEntity getByName con-338-split-2]
  set _DM(74) [pw::GridEntity getByName dom-93]
  set _DM(75) [pw::GridEntity getByName dom-73]
  set _DM(76) [pw::GridEntity getByName dom-96]
  set _DM(77) [pw::GridEntity getByName dom-76]
  set _DM(78) [pw::GridEntity getByName dom-71]
  set _DM(79) [pw::GridEntity getByName dom-91]
  set _DM(80) [pw::GridEntity getByName dom-82]
  set _DM(81) [pw::GridEntity getByName dom-80]
  set _CN(20) [pw::GridEntity getByName con-153]
  set _DM(82) [pw::GridEntity getByName dom-79]
  set _CN(21) [pw::GridEntity getByName con-150]
  set _CN(22) [pw::GridEntity getByName con-151]
  set _CN(23) [pw::GridEntity getByName con-179]
  set _DM(83) [pw::GridEntity getByName dom-69]
  set _DM(84) [pw::GridEntity getByName dom-89]
  set _DM(85) [pw::GridEntity getByName dom-39]
  set _DM(86) [pw::GridEntity getByName dom-59]
  set _DM(87) [pw::GridEntity getByName dom-94]
  set _DM(88) [pw::GridEntity getByName dom-74]
  set _DM(89) [pw::GridEntity getByName dom-90]
  set _DM(90) [pw::GridEntity getByName dom-70]
  set _DM(91) [pw::GridEntity getByName dom-95]
  set _DM(92) [pw::GridEntity getByName dom-87]
  set _DM(93) [pw::GridEntity getByName dom-67]
  set _DM(94) [pw::GridEntity getByName dom-75]
  set _DM(95) [pw::GridEntity getByName dom-72]
  set _DM(96) [pw::GridEntity getByName dom-139]
  set _DM(97) [pw::GridEntity getByName dom-131]
  set _DM(98) [pw::GridEntity getByName dom-136]
  set _DM(99) [pw::GridEntity getByName dom-151]
  set _DM(100) [pw::GridEntity getByName dom-156]
  set _DM(101) [pw::GridEntity getByName dom-120]
  set _DM(102) [pw::GridEntity getByName dom-106]
  set _DM(103) [pw::GridEntity getByName dom-103]
  set _DM(104) [pw::GridEntity getByName dom-121]
  set _DM(105) [pw::GridEntity getByName dom-123]
  set _CN(24) [pw::GridEntity getByName con-340]
  set _CN(25) [pw::GridEntity getByName con-341]
  set _DM(106) [pw::GridEntity getByName dom-25]
  set _CN(26) [pw::GridEntity getByName con-15-split-14]
  set _CN(27) [pw::GridEntity getByName con-15-split-15]
  set _CN(28) [pw::GridEntity getByName con-7-split-1-split-2-split-9]
  set _CN(29) [pw::GridEntity getByName con-273]
  set _DM(107) [pw::GridEntity getByName dom-132]
  set _CN(30) [pw::GridEntity getByName con-6-split-2-split-2-split-9]
  set _CN(31) [pw::GridEntity getByName con-6-split-2-split-2-split-10]
  set _CN(32) [pw::GridEntity getByName con-246]
  set _CN(33) [pw::GridEntity getByName con-7-split-1-split-2-split-10]
  set _CN(34) [pw::GridEntity getByName con-248]
  set _DM(108) [pw::GridEntity getByName dom-159]
  set _CN(35) [pw::GridEntity getByName con-274]
  set _CN(36) [pw::GridEntity getByName con-288]
  set _DM(109) [pw::GridEntity getByName dom-100]
  $_BL(1) setExtrusionSolverAttribute TranslateDirection {0.350601762908 1.91051346169e-07 -0.936524641345}
  $_BL(1) setExtrusionSolverAttribute TranslateDistance 0.055
  $_TMP(mode_1) run 20
$_TMP(mode_1) end
unset _TMP(mode_1)
unset _TMP(face_1)
pw::Application markUndoLevel {Extrude, Translate}


set _DM(1) [pw::GridEntity getByName dom-169]
set _DM(2) [pw::GridEntity getByName dom-126]
set _DM(3) [pw::GridEntity getByName dom-115]
set _DM(4) [pw::GridEntity getByName dom-124]
set _DM(5) [pw::GridEntity getByName dom-121]
set _DM(6) [pw::GridEntity getByName dom-92]
set _DM(7) [pw::GridEntity getByName dom-89]
set _DM(8) [pw::GridEntity getByName dom-94]
set _DM(9) [pw::GridEntity getByName dom-90]
set _DM(10) [pw::GridEntity getByName dom-93]
set _DM(11) [pw::GridEntity getByName dom-72]
set _DM(12) [pw::GridEntity getByName dom-96]
set _DM(13) [pw::GridEntity getByName dom-81]
set _DM(14) [pw::GridEntity getByName dom-82]
set _DM(15) [pw::GridEntity getByName dom-99]
set _DM(16) [pw::GridEntity getByName dom-76]
set _DM(17) [pw::GridEntity getByName dom-104]
set _DM(18) [pw::GridEntity getByName dom-105]
set _DM(19) [pw::GridEntity getByName dom-101]
set _DM(20) [pw::GridEntity getByName dom-106]
set _DM(21) [pw::GridEntity getByName dom-107]
set _DM(22) [pw::GridEntity getByName dom-114]
set _DM(23) [pw::GridEntity getByName dom-73]
set _DM(24) [pw::GridEntity getByName dom-80]
set _DM(25) [pw::GridEntity getByName dom-118]
set _DM(26) [pw::GridEntity getByName dom-120]
set _DM(27) [pw::GridEntity getByName dom-111]
set _DM(28) [pw::GridEntity getByName dom-88]
set _DM(29) [pw::GridEntity getByName dom-117]
set _DM(30) [pw::GridEntity getByName dom-116]
set _DM(31) [pw::GridEntity getByName dom-83]
set _DM(32) [pw::GridEntity getByName dom-127]
set _DM(33) [pw::GridEntity getByName dom-119]
set _DM(34) [pw::GridEntity getByName dom-91]
set _DM(35) [pw::GridEntity getByName dom-95]
set _DM(36) [pw::GridEntity getByName dom-79]
set _DM(37) [pw::GridEntity getByName dom-98]
set _DM(38) [pw::GridEntity getByName dom-100]
set _DM(39) [pw::GridEntity getByName dom-84]
set _DM(40) [pw::GridEntity getByName dom-87]
set _DM(41) [pw::GridEntity getByName dom-103]
set _DM(42) [pw::GridEntity getByName dom-108]
set _DM(43) [pw::GridEntity getByName dom-78]
set _DM(44) [pw::GridEntity getByName dom-102]
set _DM(45) [pw::GridEntity getByName dom-74]
set _DM(46) [pw::GridEntity getByName dom-77]
set _DM(47) [pw::GridEntity getByName dom-86]
set _DM(48) [pw::GridEntity getByName dom-97]
set _DM(49) [pw::GridEntity getByName dom-110]
set _DM(50) [pw::GridEntity getByName dom-125]
set _DM(51) [pw::GridEntity getByName dom-122]
set _DM(52) [pw::GridEntity getByName dom-140]
set _DM(53) [pw::GridEntity getByName dom-131]
set _DM(54) [pw::GridEntity getByName dom-21]
set _DM(55) [pw::GridEntity getByName dom-135]
set _DM(56) [pw::GridEntity getByName dom-159]
set _DM(57) [pw::GridEntity getByName dom-147]
set _DM(58) [pw::GridEntity getByName dom-30]
set _DM(59) [pw::GridEntity getByName dom-151]
set _DM(60) [pw::GridEntity getByName dom-29]
set _DM(61) [pw::GridEntity getByName dom-23]
set _DM(62) [pw::GridEntity getByName dom-129]
set _DM(63) [pw::GridEntity getByName dom-149]
set _DM(64) [pw::GridEntity getByName dom-28]
set _DM(65) [pw::GridEntity getByName dom-160]
set _DM(66) [pw::GridEntity getByName dom-132]
set _DM(67) [pw::GridEntity getByName dom-133]
set _DM(68) [pw::GridEntity getByName dom-17]
set _DM(69) [pw::GridEntity getByName dom-143]
set _DM(70) [pw::GridEntity getByName dom-25]
set _DM(71) [pw::GridEntity getByName dom-22]
set _DM(72) [pw::GridEntity getByName dom-19]
set _DM(73) [pw::GridEntity getByName dom-155]
set _DM(74) [pw::GridEntity getByName dom-134]
set _DM(75) [pw::GridEntity getByName dom-20]
set _DM(76) [pw::GridEntity getByName dom-156]
set _DM(77) [pw::GridEntity getByName dom-144]
set _DM(78) [pw::GridEntity getByName dom-157]
set _DM(79) [pw::GridEntity getByName dom-16]
set _DM(80) [pw::GridEntity getByName dom-130]
set _DM(81) [pw::GridEntity getByName dom-18]
set _DM(82) [pw::GridEntity getByName dom-150]
set _DM(83) [pw::GridEntity getByName dom-148]
set _DM(84) [pw::GridEntity getByName dom-153]
set _DM(85) [pw::GridEntity getByName dom-26]
set _DM(86) [pw::GridEntity getByName dom-138]
set _DM(87) [pw::GridEntity getByName dom-145]
set _DM(88) [pw::GridEntity getByName dom-32]
set _DM(89) [pw::GridEntity getByName dom-27]
set _DM(90) [pw::GridEntity getByName dom-146]
set _DM(91) [pw::GridEntity getByName dom-152]
set _DM(92) [pw::GridEntity getByName dom-142]
set _DM(93) [pw::GridEntity getByName dom-154]
set _DM(94) [pw::GridEntity getByName dom-158]
set _DM(95) [pw::GridEntity getByName dom-13]
set _DM(96) [pw::GridEntity getByName dom-24]
set _DM(97) [pw::GridEntity getByName dom-31]
set _DM(98) [pw::GridEntity getByName dom-12]
set _DM(99) [pw::GridEntity getByName dom-141]
set _DM(100) [pw::GridEntity getByName dom-139]
set _DM(101) [pw::GridEntity getByName dom-136]
set _DM(102) [pw::GridEntity getByName dom-137]
set _DM(103) [pw::GridEntity getByName dom-68]
set _DM(104) [pw::GridEntity getByName dom-69]
set _DM(105) [pw::GridEntity getByName dom-66]
set _DM(106) [pw::GridEntity getByName dom-67]
set _DM(107) [pw::GridEntity getByName dom-70]
set _DM(108) [pw::GridEntity getByName dom-85]
set _DM(109) [pw::GridEntity getByName dom-65]
set _DM(110) [pw::GridEntity getByName dom-4]
set _DM(111) [pw::GridEntity getByName dom-71]
set _DM(112) [pw::GridEntity getByName dom-75]
set _DM(113) [pw::GridEntity getByName dom-1]
set _DM(114) [pw::GridEntity getByName dom-168]
set _DM(115) [pw::GridEntity getByName dom-166]
set _DM(116) [pw::GridEntity getByName dom-167]
set _DM(117) [pw::GridEntity getByName dom-161]
set _DM(118) [pw::GridEntity getByName dom-162]
set _DM(119) [pw::GridEntity getByName dom-171]
set _DM(120) [pw::GridEntity getByName dom-170]
set _DM(121) [pw::GridEntity getByName dom-9]
set _DM(122) [pw::GridEntity getByName dom-6]
set _DM(123) [pw::GridEntity getByName dom-50]
set _DM(124) [pw::GridEntity getByName dom-109]
set _DM(125) [pw::GridEntity getByName dom-39]
set _DM(126) [pw::GridEntity getByName dom-14]
set _DM(127) [pw::GridEntity getByName dom-15]
set _DM(128) [pw::GridEntity getByName dom-112]
set _DM(129) [pw::GridEntity getByName dom-123]
set _DM(130) [pw::GridEntity getByName dom-5]
set _DM(131) [pw::GridEntity getByName dom-40]
set _DM(132) [pw::GridEntity getByName dom-52]
set _DM(133) [pw::GridEntity getByName dom-113]
set _DM(134) [pw::GridEntity getByName dom-128]
set _DM(135) [pw::GridEntity getByName dom-8]
set _DM(136) [pw::GridEntity getByName dom-60]
set _DM(137) [pw::GridEntity getByName dom-37]
set _DM(138) [pw::GridEntity getByName dom-7]
set _DM(139) [pw::GridEntity getByName dom-46]
set _DM(140) [pw::GridEntity getByName dom-36]
set _DM(141) [pw::GridEntity getByName dom-53]
set _DM(142) [pw::GridEntity getByName dom-47]
set _DM(143) [pw::GridEntity getByName dom-51]
set _DM(144) [pw::GridEntity getByName dom-59]
set _DM(145) [pw::GridEntity getByName dom-34]
set _DM(146) [pw::GridEntity getByName dom-58]
set _DM(147) [pw::GridEntity getByName dom-63]
set _DM(148) [pw::GridEntity getByName dom-43]
set _DM(149) [pw::GridEntity getByName dom-10]
set _DM(150) [pw::GridEntity getByName dom-56]
set _DM(151) [pw::GridEntity getByName dom-61]
set _DM(152) [pw::GridEntity getByName dom-55]
set _DM(153) [pw::GridEntity getByName dom-33]
set _DM(154) [pw::GridEntity getByName dom-62]
set _DM(155) [pw::GridEntity getByName dom-35]
set _DM(156) [pw::GridEntity getByName dom-42]
set _DM(157) [pw::GridEntity getByName dom-44]
set _DM(158) [pw::GridEntity getByName dom-57]
set _DM(159) [pw::GridEntity getByName dom-38]
set _DM(160) [pw::GridEntity getByName dom-2]
set _DM(161) [pw::GridEntity getByName dom-54]
set _DM(162) [pw::GridEntity getByName dom-11]
set _DM(163) [pw::GridEntity getByName dom-45]
set _DM(164) [pw::GridEntity getByName dom-64]
set _DM(165) [pw::GridEntity getByName dom-49]
set _DM(166) [pw::GridEntity getByName dom-48]
set _DM(167) [pw::GridEntity getByName dom-41]
set _DM(168) [pw::GridEntity getByName dom-165]
set _DM(169) [pw::GridEntity getByName dom-164]
set _DM(170) [pw::GridEntity getByName dom-163]
set _DM(171) [pw::GridEntity getByName dom-3]
set _TMP(PW_1) [pw::BlockUnstructured createFromDomains -reject _TMP(unusedDoms) -voids _TMP(voidBlocks) -baffles _TMP(baffleFaces) [concat [list] [list $_DM(1) $_DM(2) $_DM(3) $_DM(4) $_DM(5) $_DM(6) $_DM(7) $_DM(8) $_DM(9) $_DM(10) $_DM(11) $_DM(12) $_DM(13) $_DM(14) $_DM(15) $_DM(16) $_DM(17) $_DM(18) $_DM(19) $_DM(20) $_DM(21) $_DM(22) $_DM(23) $_DM(24) $_DM(25) $_DM(26) $_DM(27) $_DM(28) $_DM(29) $_DM(30) $_DM(31) $_DM(32) $_DM(33) $_DM(34) $_DM(35) $_DM(36) $_DM(37) $_DM(38) $_DM(39) $_DM(40) $_DM(41) $_DM(42) $_DM(43) $_DM(44) $_DM(45) $_DM(46) $_DM(47) $_DM(48) $_DM(49) $_DM(50) $_DM(51) $_DM(52) $_DM(53) $_DM(54) $_DM(55) $_DM(56) $_DM(57) $_DM(58) $_DM(59) $_DM(60) $_DM(61) $_DM(62) $_DM(63) $_DM(64) $_DM(65) $_DM(66) $_DM(67) $_DM(68) $_DM(69) $_DM(70) $_DM(71) $_DM(72) $_DM(73) $_DM(74) $_DM(75) $_DM(76) $_DM(77) $_DM(78) $_DM(79) $_DM(80) $_DM(81) $_DM(82) $_DM(83) $_DM(84) $_DM(85) $_DM(86) $_DM(87) $_DM(88) $_DM(89) $_DM(90) $_DM(91) $_DM(92) $_DM(93) $_DM(94) $_DM(95) $_DM(96) $_DM(97) $_DM(98) $_DM(99) $_DM(100) $_DM(101) $_DM(102) $_DM(103) $_DM(104) $_DM(105) $_DM(106) $_DM(107) $_DM(108) $_DM(109) $_DM(110) $_DM(111) $_DM(112) $_DM(113) $_DM(114) $_DM(115) $_DM(116) $_DM(117) $_DM(118) $_DM(119) $_DM(120) $_DM(121) $_DM(122) $_DM(123) $_DM(124) $_DM(125) $_DM(126) $_DM(127) $_DM(128) $_DM(129) $_DM(130) $_DM(131) $_DM(132) $_DM(133) $_DM(134) $_DM(135) $_DM(136) $_DM(137) $_DM(138) $_DM(139) $_DM(140) $_DM(141) $_DM(142) $_DM(143) $_DM(144) $_DM(145) $_DM(146) $_DM(147) $_DM(148) $_DM(149) $_DM(150) $_DM(151) $_DM(152) $_DM(153) $_DM(154) $_DM(155) $_DM(156) $_DM(157) $_DM(158) $_DM(159) $_DM(160) $_DM(161) $_DM(162) $_DM(163) $_DM(164) $_DM(165) $_DM(166) $_DM(167) $_DM(168) $_DM(169) $_DM(170) $_DM(171)]]]
unset _TMP(unusedDoms)
unset _TMP(PW_1)
pw::Application markUndoLevel {Assemble Blocks}

set _BL(1) [pw::GridEntity getByName blk-8]
set _BL(2) [pw::GridEntity getByName blk-10]
set _BL(3) [pw::GridEntity getByName blk-7]
set _BL(4) [pw::GridEntity getByName blk-11]
set _BL(5) [pw::GridEntity getByName blk-12]
pw::Entity delete [list $_BL(1) $_BL(2) $_BL(3) $_BL(4) $_BL(5)]
pw::Application markUndoLevel Delete

set _BL(1) [pw::GridEntity getByName blk-9]
set _TMP(mode_1) [pw::Application begin UnstructuredSolver [list $_BL(1)]]
  $_TMP(mode_1) setStopWhenFullLayersNotMet true
  $_TMP(mode_1) setAllowIncomplete true
  $_TMP(mode_1) run Initialize
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Initialize

set _BL(1) [pw::GridEntity getByName blk-9]
set _BL(2) [pw::GridEntity getByName blk-2]
set _BL(3) [pw::GridEntity getByName blk-5]
set _CN(1) [pw::GridEntity getByName con-338-split-1]
set _BL(4) [pw::GridEntity getByName blk-1]
set _BL(5) [pw::GridEntity getByName blk-6]
set _BL(6) [pw::GridEntity getByName blk-3]
set _BL(7) [pw::GridEntity getByName blk-4]
set _CN(2) [pw::GridEntity getByName con-338-split-2]
set _TMP(mode_1) [pw::Application begin Modify [list $_BL(1) $_BL(2) $_BL(3) $_CN(2) $_CN(1) $_BL(4) $_BL(5) $_BL(6) $_BL(7)]]
  pw::Entity transform [pwu::Transform rotation -anchor {0 0 0} [pwu::Vector3 normalize [pwu::Vector3 subtract {0 1 0} {0 0 0}]] 100.26206302] [$_TMP(mode_1) getEntities]
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Rotate

set _CN(1) [pw::GridEntity getByName con-338-split-1]
set _CN(2) [pw::GridEntity getByName con-338-split-2]
set _BL(1) [pw::GridEntity getByName blk-3]
set _BL(2) [pw::GridEntity getByName blk-6]
set _BL(3) [pw::GridEntity getByName blk-9]
set _BL(4) [pw::GridEntity getByName blk-4]
set _BL(5) [pw::GridEntity getByName blk-5]
set _BL(6) [pw::GridEntity getByName blk-2]
set _BL(7) [pw::GridEntity getByName blk-1]
set _TMP(mode_1) [pw::Application begin Modify [list $_CN(1) $_CN(2) $_BL(1) $_BL(2) $_BL(3) $_BL(4) $_BL(5) $_BL(6) $_BL(7)]]
  pw::Entity transform [pwu::Transform translation [pwu::Vector3 subtract [list 0.18414356 0.25714286 0.02914283] [list 0.037954403062924115 1.7005357580944513e-7 0.0068715638712333075]]] [$_TMP(mode_1) getEntities]
$_TMP(mode_1) end
unset _TMP(mode_1)
pw::Application markUndoLevel Translate

set _CN(1) [pw::GridEntity getByName con-341]
set _TMP(split_params) [list]
lappend _TMP(split_params) 0.50001174678663118
set _TMP(PW_1) [$_CN(1) split $_TMP(split_params)]
unset _TMP(PW_1)
pw::Application markUndoLevel {Split Into Pieces}

set _DM(1) [pw::GridEntity getByName dom-164]
set _DM(2) [pw::GridEntity getByName dom-168]
set _DM(3) [pw::GridEntity getByName dom-103]
set _DM(4) [pw::GridEntity getByName dom-111]
set _DM(5) [pw::GridEntity getByName dom-106]
set _DM(6) [pw::GridEntity getByName dom-126]
set _DM(7) [pw::GridEntity getByName dom-171]
set _DM(8) [pw::GridEntity getByName dom-161]
set _DM(9) [pw::GridEntity getByName dom-175]
set _DM(10) [pw::GridEntity getByName dom-123]
set _DM(11) [pw::GridEntity getByName dom-6]
set _DM(12) [pw::GridEntity getByName dom-20]
set _DM(13) [pw::GridEntity getByName dom-1]
set _DM(14) [pw::GridEntity getByName dom-21]
set _DM(15) [pw::GridEntity getByName dom-26]
set _DM(16) [pw::GridEntity getByName dom-169]
set _CN(1) [pw::GridEntity getByName con-340]
set _CN(2) [pw::GridEntity getByName con-341-split-1]
set _CN(3) [pw::GridEntity getByName con-341-split-2]
set _DM(17) [pw::GridEntity getByName dom-102]
set _DM(18) [pw::GridEntity getByName dom-121]
set _DM(19) [pw::GridEntity getByName dom-101]
set _DM(20) [pw::GridEntity getByName dom-152]
set _DM(21) [pw::GridEntity getByName dom-157]
set _DM(22) [pw::GridEntity getByName dom-160]
set _DM(23) [pw::GridEntity getByName dom-137]
set _DM(24) [pw::GridEntity getByName dom-140]
set _DM(25) [pw::GridEntity getByName dom-156]
set _DM(26) [pw::GridEntity getByName dom-159]
set _DM(27) [pw::GridEntity getByName dom-136]
set _DM(28) [pw::GridEntity getByName dom-139]
set _DM(29) [pw::GridEntity getByName dom-117]
set _TMP(split_params) [list]
lappend _TMP(split_params) [lindex [$_DM(2) closestCoordinate [pw::Grid getPoint [list 225 $_DM(16)]]] 0]
unset _TMP(split_params)
pw::Application markUndoLevel Split

set _DM(30) [pw::GridEntity getByName dom-154]
set _DM(31) [pw::GridEntity getByName dom-149]
set _DM(32) [pw::GridEntity getByName dom-158]
set _DM(33) [pw::GridEntity getByName dom-163]
set _DM(34) [pw::GridEntity getByName dom-141]
set _DM(35) [pw::GridEntity getByName dom-148]
set _DM(36) [pw::GridEntity getByName dom-134]
set _DM(37) [pw::GridEntity getByName dom-138]
set _DM(38) [pw::GridEntity getByName dom-129]
set _DM(39) [pw::GridEntity getByName dom-162]
set _DM(40) [pw::GridEntity getByName dom-153]
set _DM(41) [pw::GridEntity getByName dom-142]
set _DM(42) [pw::GridEntity getByName dom-133]
set _DM(43) [pw::GridEntity getByName dom-135]
set _DM(44) [pw::GridEntity getByName dom-155]
set _DM(45) [pw::GridEntity getByName dom-172]
set _DM(46) [pw::GridEntity getByName dom-166]
set _TMP(split_params) [list]
lappend _TMP(split_params) [lindex [$_DM(2) closestCoordinate [pw::Grid getPoint [list 275 $_DM(16)]]] 0]
set _TMP(PW_2) [$_DM(2) split -I $_TMP(split_params)]
unset _TMP(PW_2)
unset _TMP(split_params)
set _DM(47) [pw::GridEntity getByName dom-168-split-1]
pw::Application markUndoLevel Split

#___________________________________BOUNDARY AND VOLUME CONDITION ASSIGNMENT______________________________#

set _TMP(PW_1) [pw::VolumeCondition getByName stator]
$_TMP(PW_1) delete
unset _TMP(PW_1)
pw::Application markUndoLevel {Delete VC}

set _BL(1) [pw::GridEntity getByName blk-1]
set _BL(2) [pw::GridEntity getByName blk-2]
set _BL(3) [pw::GridEntity getByName blk-3]
set _BL(4) [pw::GridEntity getByName blk-4]
set _BL(5) [pw::GridEntity getByName blk-5]
set _BL(6) [pw::GridEntity getByName blk-6]
set _BL(7) [pw::GridEntity getByName blk-9]
set _TMP(PW_1) [pw::VolumeCondition getByName rotor]
$_TMP(PW_1) apply [list $_BL(1) $_BL(2) $_BL(3) $_BL(4) $_BL(5) $_BL(6) $_BL(7)]
pw::Application markUndoLevel {Set VC}

unset _TMP(PW_1)
set _TMP(PW_1) [pw::BoundaryCondition getByName inlet]
$_TMP(PW_1) delete
unset _TMP(PW_1)
set _TMP(PW_1) [pw::BoundaryCondition getByName outlet]
$_TMP(PW_1) delete
unset _TMP(PW_1)
set _TMP(PW_1) [pw::BoundaryCondition getByName farf]
$_TMP(PW_1) delete
unset _TMP(PW_1)
set _TMP(PW_1) [pw::BoundaryCondition getByName stator_farf]
$_TMP(PW_1) delete
unset _TMP(PW_1)
set _TMP(PW_1) [pw::BoundaryCondition getByName rotor_farf]
$_TMP(PW_1) delete
unset _TMP(PW_1)
set _TMP(PW_1) [pw::BoundaryCondition getByName stator_out]
$_TMP(PW_1) delete
unset _TMP(PW_1)
set _TMP(PW_1) [pw::BoundaryCondition getByName rotor_out]
$_TMP(PW_1) delete
unset _TMP(PW_1)
set _TMP(PW_1) [pw::BoundaryCondition getByName rotor_period_posX]
$_TMP(PW_1) delete
unset _TMP(PW_1)
set _TMP(PW_1) [pw::BoundaryCondition getByName rotor_period_negX]
$_TMP(PW_1) delete
unset _TMP(PW_1)
set _TMP(PW_1) [pw::BoundaryCondition getByName stator_period_posX]
$_TMP(PW_1) delete
unset _TMP(PW_1)
set _TMP(PW_1) [pw::BoundaryCondition getByName stator_period_negX]
$_TMP(PW_1) delete
unset _TMP(PW_1)
set _TMP(PW_1) [pw::BoundaryCondition getByName stator_in]
$_TMP(PW_1) delete
unset _TMP(PW_1)
set _TMP(PW_1) [pw::BoundaryCondition getByName rotor_in]
$_TMP(PW_1) delete
unset _TMP(PW_1)
set _TMP(PW_1) [pw::BoundaryCondition getByName Unspecified]
pw::Application markUndoLevel {Delete BC}

set _TMP(PW_2) [pw::BoundaryCondition create]
pw::Application markUndoLevel {Create BC}

unset _TMP(PW_2)
set _TMP(PW_2) [pw::BoundaryCondition create]
pw::Application markUndoLevel {Create BC}

unset _TMP(PW_2)
set _TMP(PW_2) [pw::BoundaryCondition create]
pw::Application markUndoLevel {Create BC}

unset _TMP(PW_2)
set _TMP(PW_2) [pw::BoundaryCondition getByName bc-6]
$_TMP(PW_2) delete
unset _TMP(PW_2)
pw::Application markUndoLevel {Delete BC}

set _TMP(PW_2) [pw::BoundaryCondition getByName bc-4]
$_TMP(PW_2) setName circum-rotor
pw::Application markUndoLevel {Name BC}

set _TMP(PW_3) [pw::BoundaryCondition getByName bc-5]
$_TMP(PW_3) setName in-rotor
pw::Application markUndoLevel {Name BC}

set _TMP(PW_4) [pw::BoundaryCondition create]
pw::Application markUndoLevel {Create BC}

unset _TMP(PW_4)
set _TMP(PW_4) [pw::BoundaryCondition getByName bc-6]
$_TMP(PW_4) setName out-rotor
pw::Application markUndoLevel {Name BC}

$_TMP(PW_3) setId 10
pw::Application markUndoLevel {Change BC ID}

set _TMP(PW_5) [pw::BoundaryCondition getByName prop]
$_TMP(PW_5) setId 11
pw::Application markUndoLevel {Change BC ID}

$_TMP(PW_4) setId 12
pw::Application markUndoLevel {Change BC ID}

$_TMP(PW_2) setId 12
pw::Application markUndoLevel {Change BC ID}

$_TMP(PW_5) setId 4
pw::Application markUndoLevel {Change BC ID}

$_TMP(PW_2) setId 5
pw::Application markUndoLevel {Change BC ID}

$_TMP(PW_3) setId 6
pw::Application markUndoLevel {Change BC ID}

$_TMP(PW_4) setId 7
pw::Application markUndoLevel {Change BC ID}

pw::Display hideLayer 5
unset _TMP(PW_1)
unset _TMP(PW_5)
unset _TMP(PW_2)
unset _TMP(PW_3)
unset _TMP(PW_4)
set _DM(1) [pw::GridEntity getByName dom-165]
set _DM(2) [pw::GridEntity getByName dom-47]
set _DM(3) [pw::GridEntity getByName dom-46]
set _DM(4) [pw::GridEntity getByName dom-48]
set _DM(5) [pw::GridEntity getByName dom-49]
set _DM(6) [pw::GridEntity getByName dom-77]
set _DM(7) [pw::GridEntity getByName dom-84]
set _DM(8) [pw::GridEntity getByName dom-83]
set _DM(9) [pw::GridEntity getByName dom-82]
set _DM(10) [pw::GridEntity getByName dom-164]
set _DM(11) [pw::GridEntity getByName dom-163]
set _DM(12) [pw::GridEntity getByName dom-52]
set _DM(13) [pw::GridEntity getByName dom-50]
set _DM(14) [pw::GridEntity getByName dom-45]
set _DM(15) [pw::GridEntity getByName dom-51]
set _DM(16) [pw::GridEntity getByName dom-17]
set _DM(17) [pw::GridEntity getByName dom-16]
set _DM(18) [pw::GridEntity getByName dom-14]
set _DM(19) [pw::GridEntity getByName dom-15]
set _DM(20) [pw::GridEntity getByName dom-79]
set _DM(21) [pw::GridEntity getByName dom-80]
set _DM(22) [pw::GridEntity getByName dom-78]
set _DM(23) [pw::GridEntity getByName dom-81]
set _DM(24) [pw::GridEntity getByName dom-161]
set _DM(25) [pw::GridEntity getByName dom-162]
set _DM(26) [pw::GridEntity getByName dom-146]
set _DM(27) [pw::GridEntity getByName dom-141]
set _DM(28) [pw::GridEntity getByName dom-147]
set _DM(29) [pw::GridEntity getByName dom-148]
set _DM(30) [pw::GridEntity getByName dom-20]
set _DM(31) [pw::GridEntity getByName dom-19]
set _DM(32) [pw::GridEntity getByName dom-18]
set _DM(33) [pw::GridEntity getByName dom-13]
set _DM(34) [pw::GridEntity getByName dom-110]
set _DM(35) [pw::GridEntity getByName dom-112]
set _DM(36) [pw::GridEntity getByName dom-111]
set _DM(37) [pw::GridEntity getByName dom-113]
set _DM(38) [pw::GridEntity getByName dom-115]
set _DM(39) [pw::GridEntity getByName dom-109]
set _DM(40) [pw::GridEntity getByName dom-116]
set _DM(41) [pw::GridEntity getByName dom-114]
set _DM(42) [pw::GridEntity getByName dom-145]
set _DM(43) [pw::GridEntity getByName dom-143]
set _DM(44) [pw::GridEntity getByName dom-142]
set _DM(45) [pw::GridEntity getByName dom-144]
set _TMP(PW_1) [pw::BoundaryCondition getByName hub]
$_TMP(PW_1) apply [list [list $_BL(7) $_DM(25)] [list $_BL(7) $_DM(24)] [list $_BL(7) $_DM(11)] [list $_BL(7) $_DM(1)] [list $_BL(7) $_DM(10)] [list $_BL(1) $_DM(18)] [list $_BL(1) $_DM(33)] [list $_BL(1) $_DM(19)] [list $_BL(1) $_DM(30)] [list $_BL(1) $_DM(31)] [list $_BL(1) $_DM(16)] [list $_BL(1) $_DM(17)] [list $_BL(1) $_DM(32)] [list $_BL(2) $_DM(14)] [list $_BL(2) $_DM(4)] [list $_BL(2) $_DM(2)] [list $_BL(2) $_DM(5)] [list $_BL(2) $_DM(13)] [list $_BL(2) $_DM(12)] [list $_BL(2) $_DM(15)] [list $_BL(2) $_DM(3)] [list $_BL(3) $_DM(21)] [list $_BL(3) $_DM(20)] [list $_BL(3) $_DM(23)] [list $_BL(3) $_DM(9)] [list $_BL(3) $_DM(8)] [list $_BL(3) $_DM(7)] [list $_BL(3) $_DM(6)] [list $_BL(3) $_DM(22)] [list $_BL(4) $_DM(35)] [list $_BL(4) $_DM(37)] [list $_BL(4) $_DM(34)] [list $_BL(4) $_DM(36)] [list $_BL(4) $_DM(41)] [list $_BL(4) $_DM(38)] [list $_BL(4) $_DM(39)] [list $_BL(4) $_DM(40)] [list $_BL(5) $_DM(45)] [list $_BL(5) $_DM(44)] [list $_BL(5) $_DM(43)] [list $_BL(5) $_DM(26)] [list $_BL(5) $_DM(27)] [list $_BL(5) $_DM(28)] [list $_BL(5) $_DM(42)] [list $_BL(5) $_DM(29)]]
pw::Application markUndoLevel {Set BC}

set _DM(46) [pw::GridEntity getByName dom-170]
set _TMP(PW_2) [pw::BoundaryCondition getByName Unspecified]
$_TMP(PW_2) apply [list [list $_BL(6) $_DM(46)] [list $_BL(7) $_DM(25)] [list $_BL(7) $_DM(24)] [list $_BL(7) $_DM(11)] [list $_BL(7) $_DM(1)] [list $_BL(7) $_DM(10)] [list $_BL(1) $_DM(18)] [list $_BL(1) $_DM(33)] [list $_BL(1) $_DM(19)] [list $_BL(1) $_DM(30)] [list $_BL(1) $_DM(31)] [list $_BL(1) $_DM(16)] [list $_BL(1) $_DM(17)] [list $_BL(1) $_DM(32)] [list $_BL(2) $_DM(14)] [list $_BL(2) $_DM(4)] [list $_BL(2) $_DM(2)] [list $_BL(2) $_DM(5)] [list $_BL(2) $_DM(13)] [list $_BL(2) $_DM(12)] [list $_BL(2) $_DM(15)] [list $_BL(2) $_DM(3)] [list $_BL(3) $_DM(21)] [list $_BL(3) $_DM(20)] [list $_BL(3) $_DM(23)] [list $_BL(3) $_DM(9)] [list $_BL(3) $_DM(8)] [list $_BL(3) $_DM(7)] [list $_BL(3) $_DM(6)] [list $_BL(3) $_DM(22)] [list $_BL(4) $_DM(35)] [list $_BL(4) $_DM(37)] [list $_BL(4) $_DM(34)] [list $_BL(4) $_DM(36)] [list $_BL(4) $_DM(41)] [list $_BL(4) $_DM(38)] [list $_BL(4) $_DM(39)] [list $_BL(4) $_DM(40)] [list $_BL(5) $_DM(45)] [list $_BL(5) $_DM(44)] [list $_BL(5) $_DM(43)] [list $_BL(5) $_DM(26)] [list $_BL(5) $_DM(27)] [list $_BL(5) $_DM(28)] [list $_BL(5) $_DM(42)] [list $_BL(5) $_DM(29)]]
pw::Application markUndoLevel {Set BC}

$_TMP(PW_1) apply [list [list $_BL(6) $_DM(46)] [list $_BL(7) $_DM(25)] [list $_BL(7) $_DM(24)] [list $_BL(7) $_DM(11)] [list $_BL(7) $_DM(1)] [list $_BL(7) $_DM(10)] [list $_BL(1) $_DM(18)] [list $_BL(1) $_DM(33)] [list $_BL(1) $_DM(19)] [list $_BL(1) $_DM(30)] [list $_BL(1) $_DM(31)] [list $_BL(1) $_DM(16)] [list $_BL(1) $_DM(17)] [list $_BL(1) $_DM(32)] [list $_BL(2) $_DM(14)] [list $_BL(2) $_DM(4)] [list $_BL(2) $_DM(2)] [list $_BL(2) $_DM(5)] [list $_BL(2) $_DM(13)] [list $_BL(2) $_DM(12)] [list $_BL(2) $_DM(15)] [list $_BL(2) $_DM(3)] [list $_BL(3) $_DM(21)] [list $_BL(3) $_DM(20)] [list $_BL(3) $_DM(23)] [list $_BL(3) $_DM(9)] [list $_BL(3) $_DM(8)] [list $_BL(3) $_DM(7)] [list $_BL(3) $_DM(6)] [list $_BL(3) $_DM(22)] [list $_BL(4) $_DM(35)] [list $_BL(4) $_DM(37)] [list $_BL(4) $_DM(34)] [list $_BL(4) $_DM(36)] [list $_BL(4) $_DM(41)] [list $_BL(4) $_DM(38)] [list $_BL(4) $_DM(39)] [list $_BL(4) $_DM(40)] [list $_BL(5) $_DM(45)] [list $_BL(5) $_DM(44)] [list $_BL(5) $_DM(43)] [list $_BL(5) $_DM(26)] [list $_BL(5) $_DM(27)] [list $_BL(5) $_DM(28)] [list $_BL(5) $_DM(42)] [list $_BL(5) $_DM(29)]]
pw::Application markUndoLevel {Set BC}

set _DM(47) [pw::GridEntity getByName dom-2]
set _DM(48) [pw::GridEntity getByName dom-43]
set _DM(49) [pw::GridEntity getByName dom-8]
set _DM(50) [pw::GridEntity getByName dom-11]
set _DM(51) [pw::GridEntity getByName dom-3]
set _DM(52) [pw::GridEntity getByName dom-67]
set _DM(53) [pw::GridEntity getByName dom-75]
set _DM(54) [pw::GridEntity getByName dom-66]
set _DM(55) [pw::GridEntity getByName dom-72]
set _DM(56) [pw::GridEntity getByName dom-98]
set _DM(57) [pw::GridEntity getByName dom-99]
set _DM(58) [pw::GridEntity getByName dom-104]
set _DM(59) [pw::GridEntity getByName dom-107]
set _DM(60) [pw::GridEntity getByName dom-136]
set _DM(61) [pw::GridEntity getByName dom-139]
set _DM(62) [pw::GridEntity getByName dom-130]
set _DM(63) [pw::GridEntity getByName dom-131]
set _DM(64) [pw::GridEntity getByName dom-1]
set _DM(65) [pw::GridEntity getByName dom-65]
set _DM(66) [pw::GridEntity getByName dom-42]
set _DM(67) [pw::GridEntity getByName dom-44]
set _DM(68) [pw::GridEntity getByName dom-38]
set _DM(69) [pw::GridEntity getByName dom-6]
set _DM(70) [pw::GridEntity getByName dom-9]
set _DM(71) [pw::GridEntity getByName dom-7]
set _DM(72) [pw::GridEntity getByName dom-5]
set _DM(73) [pw::GridEntity getByName dom-4]
set _DM(74) [pw::GridEntity getByName dom-10]
set _DM(75) [pw::GridEntity getByName dom-12]
set _DM(76) [pw::GridEntity getByName dom-73]
set _DM(77) [pw::GridEntity getByName dom-74]
set _DM(78) [pw::GridEntity getByName dom-71]
set _DM(79) [pw::GridEntity getByName dom-70]
set _DM(80) [pw::GridEntity getByName dom-76]
set _DM(81) [pw::GridEntity getByName dom-69]
set _DM(82) [pw::GridEntity getByName dom-68]
set _DM(83) [pw::GridEntity getByName dom-102]
set _DM(84) [pw::GridEntity getByName dom-101]
set _DM(85) [pw::GridEntity getByName dom-97]
set _DM(86) [pw::GridEntity getByName dom-100]
set _DM(87) [pw::GridEntity getByName dom-106]
set _DM(88) [pw::GridEntity getByName dom-103]
set _DM(89) [pw::GridEntity getByName dom-105]
set _DM(90) [pw::GridEntity getByName dom-108]
set _DM(91) [pw::GridEntity getByName dom-133]
set _DM(92) [pw::GridEntity getByName dom-134]
set _DM(93) [pw::GridEntity getByName dom-137]
set _DM(94) [pw::GridEntity getByName dom-135]
set _DM(95) [pw::GridEntity getByName dom-129]
set _DM(96) [pw::GridEntity getByName dom-132]
set _DM(97) [pw::GridEntity getByName dom-140]
set _DM(98) [pw::GridEntity getByName dom-138]
set _DM(99) [pw::GridEntity getByName dom-36]
set _DM(100) [pw::GridEntity getByName dom-41]
set _DM(101) [pw::GridEntity getByName dom-35]
set _DM(102) [pw::GridEntity getByName dom-40]
set _DM(103) [pw::GridEntity getByName dom-34]
set _DM(104) [pw::GridEntity getByName dom-39]
set _DM(105) [pw::GridEntity getByName dom-37]
set _DM(106) [pw::GridEntity getByName dom-33]
set _TMP(PW_3) [pw::BoundaryCondition getByName prop]
$_TMP(PW_3) apply [list [list $_BL(1) $_DM(47)] [list $_BL(1) $_DM(51)] [list $_BL(1) $_DM(73)] [list $_BL(1) $_DM(64)] [list $_BL(1) $_DM(71)] [list $_BL(1) $_DM(72)] [list $_BL(1) $_DM(69)] [list $_BL(1) $_DM(49)] [list $_BL(1) $_DM(70)] [list $_BL(1) $_DM(74)] [list $_BL(1) $_DM(50)] [list $_BL(1) $_DM(75)] [list $_BL(2) $_DM(106)] [list $_BL(2) $_DM(103)] [list $_BL(2) $_DM(48)] [list $_BL(2) $_DM(67)] [list $_BL(2) $_DM(102)] [list $_BL(2) $_DM(100)] [list $_BL(2) $_DM(101)] [list $_BL(2) $_DM(99)] [list $_BL(2) $_DM(66)] [list $_BL(2) $_DM(104)] [list $_BL(2) $_DM(105)] [list $_BL(2) $_DM(68)] [list $_BL(3) $_DM(52)] [list $_BL(3) $_DM(82)] [list $_BL(3) $_DM(79)] [list $_BL(3) $_DM(65)] [list $_BL(3) $_DM(54)] [list $_BL(3) $_DM(78)] [list $_BL(3) $_DM(81)] [list $_BL(3) $_DM(55)] [list $_BL(3) $_DM(76)] [list $_BL(3) $_DM(77)] [list $_BL(3) $_DM(80)] [list $_BL(3) $_DM(53)] [list $_BL(4) $_DM(87)] [list $_BL(4) $_DM(83)] [list $_BL(4) $_DM(84)] [list $_BL(4) $_DM(56)] [list $_BL(4) $_DM(57)] [list $_BL(4) $_DM(90)] [list $_BL(4) $_DM(86)] [list $_BL(4) $_DM(58)] [list $_BL(4) $_DM(85)] [list $_BL(4) $_DM(59)] [list $_BL(4) $_DM(88)] [list $_BL(4) $_DM(89)] [list $_BL(5) $_DM(62)] [list $_BL(5) $_DM(91)] [list $_BL(5) $_DM(92)] [list $_BL(5) $_DM(94)] [list $_BL(5) $_DM(60)] [list $_BL(5) $_DM(63)] [list $_BL(5) $_DM(95)] [list $_BL(5) $_DM(96)] [list $_BL(5) $_DM(98)] [list $_BL(5) $_DM(97)] [list $_BL(5) $_DM(61)] [list $_BL(5) $_DM(93)]]
pw::Application markUndoLevel {Set BC}

set _DM(107) [pw::GridEntity getByName dom-173]
set _DM(108) [pw::GridEntity getByName dom-172]
set _DM(109) [pw::GridEntity getByName dom-166]
set _DM(110) [pw::GridEntity getByName dom-167]
set _TMP(PW_4) [pw::BoundaryCondition getByName circum-rotor]
$_TMP(PW_4) apply [list [list $_BL(6) $_DM(107)] [list $_BL(6) $_DM(108)] [list $_BL(7) $_DM(109)] [list $_BL(7) $_DM(110)]]
pw::Application markUndoLevel {Set BC}

set _DM(111) [pw::GridEntity getByName dom-174]
set _DM(112) [pw::GridEntity getByName dom-175]
set _TMP(PW_5) [pw::BoundaryCondition getByName out-rotor]
$_TMP(PW_5) apply [list [list $_BL(6) $_DM(111)] [list $_BL(6) $_DM(112)]]
pw::Application markUndoLevel {Set BC}

set _DM(113) [pw::GridEntity getByName dom-169]
set _DM(114) [pw::GridEntity getByName dom-168-split-1]
set _DM(115) [pw::GridEntity getByName dom-168-split-2]
set _TMP(PW_6) [pw::BoundaryCondition getByName in-rotor]
$_TMP(PW_6) apply [list [list $_BL(7) $_DM(113)] [list $_BL(7) $_DM(114)] [list $_BL(7) $_DM(115)]]
pw::Application markUndoLevel {Set BC}

unset _TMP(PW_2)
unset _TMP(PW_3)
unset _TMP(PW_1)
unset _TMP(PW_4)
unset _TMP(PW_6)
unset _TMP(PW_5)
pw::Display showLayer 5

#________________________________________SAVING AND EXPORTING TO .CAS FILE________________________________________#

# # # Reporting Quality metrics (just inflation block for now)
# proc exportMetric {metric metricType blkName} {
#   set _BL(1) [pw::GridEntity getByName $blkName]
#   set _TMP(exam_1) [pw::Examine create $metric]
#   $_TMP(exam_1) addEntity [list $_BL(1)]
#   $_TMP(exam_1) examine
#   set Val [$_TMP(exam_1) get$metricType -entity entVar -location locVar]
#   puts "$metricType $metric: $Val"
# #   puts $entVar
# #   puts $locVar
#   $_TMP(exam_1) delete
#   unset _TMP(exam_1)   
# }

# exportMetric BlockAspectRatio Maximum blk-1
# exportMetric BlockMinimumAngle Minimum blk-1
# exportMetric BlockFidelityExpansionRatio Maximum blk-1


# Saving .pw file
pw::Application save $PW_full_path

# Exporting to .cas file
set _TMP(mode_1) [pw::Application begin CaeExport]
  $_TMP(mode_1) addAllEntities
  $_TMP(mode_1) initialize -strict -type CAE $export_full_path
  $_TMP(mode_1) verify
  $_TMP(mode_1) write
$_TMP(mode_1) end
unset _TMP(mode_1)

# #________________________________________SAVE AND EXPORT -- COMPLETE________________________________________#
