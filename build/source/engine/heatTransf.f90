module heatTransf_module
USE nrtype
! physical constants
USE multiconst,only:&
                    sb,          & ! Stefan Boltzman constant      (W m-2 K-4)
                    Em_Sno,      & ! emissivity of snow            (-)
                    Cp_air,      & ! specific heat of air          (J kg-1 K-1)
                    LH_fus,      & ! latent heat of fusion         (J kg-1)
                    LH_vap,      & ! latent heat of vaporization   (J kg-1)
                    LH_sub,      & ! latent heat of sublimation    (J kg-1)
                    Tfreeze,     & ! freezing point of pure water  (K)
                    iden_air,    & ! intrinsic density of air      (kg m-3)
                    iden_ice,    & ! intrinsic density of ice      (kg m-3)
                    iden_water     ! intrinsic density of water    (kg m-3)
! named variables for snow and soil
USE data_struc,only:ix_soil,ix_snow                        ! names variables for snow and soil
! provide access to look-up values for model decisions
USE mDecisions_module,only:      &
 ! look-up values for the numerical method
 iterative,                      & ! iterative
 nonIterative,                   & ! non-iterative
 iterSurfEnergyBal,              & ! iterate only on the surface energy balance
 ! look-up values for method used to compute derivative
 numerical,                      & ! numerical solution
 analytical,                     & ! analytical solution
 ! look-up values for choice of boundary conditions for thermodynamics
 prescribedTemp,                 & ! prescribed temperature
 energyFlux,                     & ! energy flux
 zeroFlux,                       & ! zero flux
 ! look-up values for choice of boundary conditions for soil hydrology
 prescribedHead,                 & ! prescribed head
 ! look-up values for the choice of groundwater parameterization
 equilWaterTable,                & ! equilibrium water table
 pseudoWaterTable,               & ! pseudo water table
 bigBucket,                      & ! a big bucket (lumped aquifer model)
 noExplicit                        ! no explicit groundwater parameterization
! -------------------------------------------------------------------------------------------------
implicit none
private
public::heatTransf
! local parameters
real(dp),parameter            :: RHsurf=1._dp             ! relative humidity of the surface (-)
! number of soil and snow layers
integer(i4b)                  :: nSoil                    ! number of soil layers
integer(i4b)                  :: nSnow                    ! number of snow layers
integer(i4b)                  :: nLayers                  ! total number of layers
contains


 ! ************************************************************************************************
 ! new subroutine: compute change in temperature over the time step
 ! ************************************************************************************************
 subroutine heatTransf(&
                       ! input
                       dt,                       & ! intent(in): time step (seconds)
                       iter,                     & ! intent(in): current iteration count
                       scalarVegetationTempIter, & ! intent(in): trial vegetation temperature at the current iteration (K)
                       mLayerTempIter,           & ! intent(in): trial temperature at the current iteration (K)
                       mLayerVolFracIceIter,     & ! intent(in): volumetric fraction of ice at the current iteration (-)
                       mLayerVolFracLiqIter,     & ! intent(in): volumetric fraction of liquid water at the current iteration (-)
                       mLayerMatricHeadIter,     & ! intent(in): matric head at the current iteration (m)
                       ! output
                       mLayerTempDiff,           & ! intent(out): iteration increment for temperature (K)
                       scalarVegetationTempNew,  & ! intent(out): new vegetation temperature (K)
                       mLayerTempNew,            & ! intent(out): new temperature (K)
                       mLayerVolFracIceNew,      & ! intent(out): new volumetric fraction of ice (-)
                       mLayerVolFracLiqNew,      & ! intent(out): new volumetric fraction of liquid water (-)
                       mLayerMatricHeadNew,      & ! intent(out): new matric head (m)
                       err,message)                ! intent(out): error control
 ! model decisions
 USE data_struc,only:model_decisions                            ! model decision structure
 USE var_lookup,only:iLookDECISIONS                             ! named variables for elements of the decision structure
 ! model variables, parameters, forcing data, etc.
 USE data_struc,only:attr_data,mpar_data,forc_data,mvar_data,indx_data    ! data structures
 USE var_lookup,only:iLookATTR,iLookPARAM,iLookFORCE,iLookMVAR,iLookINDEX ! named variables for structure elements
 ! compute change in temperature over the time step
 implicit none
 ! input
 real(dp),intent(in)           :: dt                       ! time step (seconds)
 integer(i4b),intent(in)       :: iter                     ! iteration count
 real(dp),intent(in)           :: scalarVegetationTempIter ! trial vegetation temperature at the current iteration (K)
 real(dp),intent(in)           :: mLayerTempIter(:)        ! trial temperature at the current iteration (K)
 real(dp),intent(in)           :: mLayerVolFracIceIter(:)  ! volumetric fraction of ice at the current iteration (-)
 real(dp),intent(in)           :: mLayerVolFracLiqIter(:)  ! volumetric fraction of liquid water at the current iteration (-)
 real(dp),intent(in)           :: mLayerMatricHeadIter(:)  ! matric head at the current iteration (m)
 ! output
 real(dp),intent(out)          :: mLayerTempDiff(:)        ! iteration increment for temperature (K)
 real(dp),intent(out)          :: scalarVegetationTempNew  ! new vegetation temperature (K)
 real(dp),intent(out)          :: mLayerTempNew(:)         ! new temperature (K)
 real(dp),intent(out)          :: mLayerVolFracIceNew(:)   ! new volumetric fraction of ice (-)
 real(dp),intent(out)          :: mLayerVolFracLiqNew(:)   ! new volumetric fraction of liquid water (-)
 real(dp),intent(out)          :: mLayerMatricHeadNew(:)   ! new matric head (m)
 integer(i4b),intent(out)      :: err                      ! error code
 character(*),intent(out)      :: message                  ! error message
 ! internal
 character(LEN=256)            :: cmessage                 ! error message of downwind routine
 ! initialize error control
 err=0; message="heatTransf/"

 ! define number of layers
 nSoil   = count(indx_data%var(iLookINDEX%layerType)%dat == ix_soil)  ! number of soil layers
 nSnow   = count(indx_data%var(iLookINDEX%layerType)%dat == ix_snow)  ! number of snow layers
 nLayers = indx_data%var(iLookINDEX%nLayers)%dat(1)                   ! total number of layers

 ! *****
 ! wrapper for the temperature change sub-routine...
 ! *************************************************
 ! used as a trick to both
 !  1) save typing; and
 !  2) "protect" variables through the use of the intent attribute
 call heatTransf_muster(&
                        ! input variables from heatTransf routine
                        dt,                                                        & ! intent(in): time step (seconds)
                        iter,                                                      & ! intent(in): current iteration count
                        scalarVegetationTempIter,                                  & ! intent(in): trial vegetation temperature at the current iteration (K)
                        mLayerTempIter,                                            & ! intent(in): trial temperature at the current iteration (K)
                        mLayerVolFracIceIter,                                      & ! intent(in): volumetric fraction of ice at the current iteration (-)
                        mLayerVolFracLiqIter,                                      & ! intent(in): volumetric fraction of liquid water at the current iteration (-)
                        mLayerMatricHeadIter,                                      & ! intent(in): matric head at the current iteration (m)
                        ! model decisions
                        model_decisions(iLookDECISIONS%num_method)%iDecision,      & ! intent(in): choice of numerical method
                        model_decisions(iLookDECISIONS%fDerivMeth)%iDecision,      & ! intent(in): method used to calculate flux derivatives
                        model_decisions(iLookDECISIONS%bcUpprTdyn)%iDecision,      & ! intent(in): type of upper boundary condition for thermodynamics
                        model_decisions(iLookDECISIONS%bcLowrTdyn)%iDecision,      & ! intent(in): type of lower boundary condition for thermodynamics
                        model_decisions(iLookDECISIONS%bcUpprSoiH)%iDecision,      & ! intent(in): type of upper boundary condition for soil hydrology
                        model_decisions(iLookDECISIONS%groundwatr)%iDecision,      & ! intent(in): groundwater parameterization
                        ! index variables
                        indx_data%var(iLookINDEX%nLayers)%dat(1),                  & ! intent(in): number of layers
                        indx_data%var(iLookINDEX%layerType)%dat,                   & ! intent(in): layer type (ix_soil or ix_snow)
                        ! general model parameters
                        attr_data%var(iLookATTR%mHeight),                          & ! intent(in): measurement height (m)
                        mpar_data%var(iLookPARAM%wimplicit),                       & ! intent(in): weight assigned to start-of-step fluxes (-)
                        mpar_data%var(iLookPARAM%snowfrz_scale),                   & ! intent(in): scaling parameter for the snow freezing curve (K-1)
                        mpar_data%var(iLookPARAM%lowerBoundTemp),                  & ! intent(in): temperature of the lower boundary (K)
                        ! soil parameters
                        mpar_data%var(iLookPARAM%vGn_alpha),                       & ! intent(in): van Genutchen "alpha" parameter (m-1)
                        mpar_data%var(iLookPARAM%vGn_n),                           & ! intent(in): van Genutchen "n" parameter (-)
                        mpar_data%var(iLookPARAM%theta_sat),                       & ! intent(in): soil porosity (-)
                        mpar_data%var(iLookPARAM%theta_res),                       & ! intent(in): soil residual volumetric water content (-)
                        ! model variables that are constant over the simulation period
                        mvar_data%var(iLookMVAR%scalarVGn_m)%dat(1),               & ! intent(in): van Genutchen "m" parameter (-)
                        mvar_data%var(iLookMVAR%mLayerRootDensity)%dat,            & ! intent(in): root density in each layer (-)
                        mvar_data%var(iLookMVAR%scalarAquiferRootFrac)%dat(1),     & ! intent(in): fraction of roots below the lowest unsaturated layer (-)
                        ! model forcing variables
                        forc_data%var(iLookFORCE%SWRadAtm),                        & ! intent(in): downward shortwave radiation (W m-2)
                        forc_data%var(iLookFORCE%LWRadAtm),                        & ! intent(in): downward longwave radiation (W m-2)
                        forc_data%var(iLookFORCE%airtemp),                         & ! intent(in): air temperature at 2 meter height (K)
                        forc_data%var(iLookFORCE%windspd),                         & ! intent(in): wind speed at 10 meter height (m s-1)
                        forc_data%var(iLookFORCE%airpres),                         & ! intent(in): air pressure at 2 meter height (Pa)
                        forc_data%var(iLookFORCE%spechum),                         & ! intent(in): specific humidity at 2 meter height (g g-1)
                        ! model state variables
                        mvar_data%var(iLookMVAR%scalarAlbedo)%dat(1),              & ! intent(in): surface albedo (-)
                        mvar_data%var(iLookMVAR%mLayerTemp)%dat,                   & ! intent(in): temperature of each layer (K)
                        mvar_data%var(iLookMVAR%mLayerVolFracIce)%dat,             & ! intent(in): volumetric fraction of ice in each layer (-)
                        ! model cooordinate variables (input)
                        mvar_data%var(iLookMVAR%mLayerDepth)%dat,                  & ! intent(in): depth of each layer (m)
                        mvar_data%var(iLookMVAR%mLayerHeight)%dat,                 & ! intent(in): height at the mid-point of each layer (m)
                        mvar_data%var(iLookMVAR%iLayerHeight)%dat,                 & ! intent(in): height at the interface of each layer (m)
                        ! model diagnostic variables (input)
                        mvar_data%var(iLookMVAR%spectralIncomingDirect)%dat,       & ! intent(in): downwelling direct shortwave radiation for all wave bands (W m-2)
                        mvar_data%var(iLookMVAR%spectralIncomingDiffuse)%dat,      & ! intent(in): downwelling diffuse shortwave radiation for all wave bands (W m-2)
                        mvar_data%var(iLookMVAR%scalarTranspireLim)%dat(1),        & ! intent(in): aggregate soil moist & veg limit on transpiration, weighted by root density (-)
                        mvar_data%var(iLookMVAR%mLayerTranspireLim)%dat,           & ! intent(in): moisture avail factor limiting transpiration in each layer (-)
                        mvar_data%var(iLookMVAR%scalarTranspireLimAqfr)%dat(1),    & ! intent(in): factor limiting transpiration in the aquifer (-)
                        mvar_data%var(iLookMVAR%iLayerThermalC)%dat,               & ! intent(in): thermal conductivity at the interface of each layer (W m-1 K-1)
                        mvar_data%var(iLookMVAR%mLayerVolHtCapBulk)%dat,           & ! intent(in): bulk volumetric heat capacity (J m-3 K-1)
                        mvar_data%var(iLookMVAR%mLayerTcrit)%dat,                  & ! intent(in): critical soil temperature above which all water is unfrozen (K)
                        ! model diagnostic variables (output)
                        mvar_data%var(iLookMVAR%mLayerdTheta_dTk)%dat,             & ! intent(out): derivative in the freezing curve (K-1)
                        mvar_data%var(iLookMVAR%mLayerInitTranspire)%dat,          & ! intent(out): transpiration loss from each soil layer at the start of the step (m s-1)
                        mvar_data%var(iLookMVAR%mLayerTranspire)%dat,              & ! intent(out): transpiration loss from each soil layer (m s-1)
                        mvar_data%var(iLookMVAR%iLayerInitNrgFlux)%dat,            & ! intent(out): energy flux at layer interfaces at the start of the time step (W m-2)
                        mvar_data%var(iLookMVAR%iLayerNrgFlux)%dat,                & ! intent(out): energy flux at layer interfaces at the end of the time step (W m-2)
                        ! diagnostic scalar variables (output)
                        mvar_data%var(iLookMVAR%scalarInitAquiferTranspire)%dat(1),& ! intent(out): transpiration loss from the aquifer at the start-of-step (m s-1)
                        mvar_data%var(iLookMVAR%scalarAquiferTranspire)%dat(1),    & ! intent(out): transpiration loss from the aquifer at the end-of-step (m s-1)
                        ! output variables from heatTransf subroutine
                        mLayerTempDiff,                                            & ! intent(out): iteration increment for temperature (K) 
                        scalarVegetationTempNew,                                   & ! intent(out): new vegetation temperature (K)
                        mLayerTempNew,                                             & ! intent(out): new temperature (K)
                        mLayerVolFracIceNew,                                       & ! intent(out): new volumetric fraction of ice (-)
                        mLayerVolFracLiqNew,                                       & ! intent(out): new volumetric fraction of liquid water (-)
                        mLayerMatricHeadNew,                                       & ! intent(out): new matric head (m)
                        err,cmessage)                                                ! intent(out): error control
 ! check for errors
 if(err/=0)then; message=trim(message)//trim(cmessage); return; endif

 end subroutine heatTransf



 
 ! ************************************************************************************************
 ! ************************************************************************************************
 ! ************************************************************************************************
 ! ***** PRIVATE SUBROUTINES **********************************************************************
 ! ************************************************************************************************
 ! ************************************************************************************************
 ! ************************************************************************************************

 ! ************************************************************************************************
 ! private subroutine: wrapper for the temperature change subroutine
 ! ************************************************************************************************
 subroutine heatTransf_muster(&
                              ! input variables from heatTransf routine
                              dt,                           & ! intent(in): time step (seconds)
                              iter,                         & ! intent(in): current iteration count
                              scalarVegetationTempIter,     & ! intent(in): trial vegetation temperature (K)
                              mLayerTempIter,               & ! intent(in): trial temperature at the current iteration (K)
                              mLayerVolFracIceIter,         & ! intent(in): volumetric fraction of ice at the current iteration (-)
                              mLayerVolFracLiqIter,         & ! intent(in): volumetric fraction of liquid water at the current iteration (-)
                              mLayerMatricHeadIter,         & ! intent(in): matric head at the current iteration (m)
                              ! model decisions
                              num_method,                   & ! intent(in): choice of numerical method
                              fDerivMeth,                   & ! intent(in): method used to calculate flux derivatives
                              bcUpprTdyn,                   & ! intent(in): type of upper boundary condition for thermodynamics
                              bcLowrTdyn,                   & ! intent(in): type of lower boundary condition for thermodynamics
                              bcUpprSoiH,                   & ! intent(in): type of upper boundary condition for soil hydrology
                              ixGroundwater,                & ! intent(in): choice of groundwater parameterization
                              ! index variables
                              nLayers,                      & ! intent(in): number of layers
                              layerType,                    & ! intent(in): layer type (ix_soil or ix_snow)
                              ! general model parameters
                              mHeight,                      & ! intent(in): measurement height (m)
                              wimplicit,                    & ! intent(in): weight assigned to start-of-step fluxes (-)
                              snowfrz_scale,                & ! intent(in): scaling parameter for the snow freezing curve (K-1)
                              lowerBoundTemp,               & ! intent(in): temperature of the lower boundary (K)
                              ! soil parameters
                              vGn_alpha,                    & ! intent(in): van Genutchen "alpha" parameter (m-1)
                              vGn_n,                        & ! intent(in): van Genutchen "n" parameter (-)
                              theta_sat,                    & ! intent(in): soil porosity (-)
                              theta_res,                    & ! intent(in): soil residual volumetric water content (-)
                              ! model variables that are constant over the simulation period
                              vGn_m,                        & ! intent(in): van Genutchen "m" parameter (-)
                              mLayerRootDensity,            & ! intent(in): root density in each layer (-)
                              scalarAquiferRootFrac,        & ! intent(in): fraction of roots below the lowest unsaturated layer (-)
                              ! model forcing variables
                              sw_down,                      & ! intent(in): downward shortwave radiation (W m-2)
                              lw_down,                      & ! intent(in): downward longwave radiation (W m-2)
                              airtemp,                      & ! intent(in): air temperature at 2 meter height (K)
                              windspd,                      & ! intent(in): wind speed at 10 meter height (m s-1)
                              airpres,                      & ! intent(in): air pressure at 2 meter height (Pa)
                              spechum,                      & ! intent(in): specific humidity at 2 meter height (g g-1)
                              ! model state variables
                              scalarAlbedo,                 & ! intent(in): surface albedo (-)
                              mLayerTemp,                   & ! intent(in): temperature of each layer (K)
                              mLayerVolFracIce,             & ! intent(in): volumetric fraction of ice in each layer (-)
                              ! model cooordinate variables (input)
                              mLayerDepth,                  & ! intent(in): depth of each layer (m)
                              mLayerHeight,                 & ! intent(in): height at the mid-point of each layer (m)
                              iLayerHeight,                 & ! intent(in): height at the interface of each layer (m)
                              ! model diagnostic variables (input)
                              spectralIncomingDirect,       & ! intent(in): downwelling direct shortwave radiation for all wave bands (W m-2)
                              spectralIncomingDiffuse,      & ! intent(in): downwelling diffuse shortwave radiation for all wave bands (W m-2)
                              scalarTranspireLim,           & ! intent(in): aggregate soil moist & veg limit on transpiration, weighted by root density (-)
                              mLayerTranspireLim,           & ! intent(in): moisture avail factor limiting transpiration in each layer (-)
                              scalarTranspireLimAqfr,       & ! intent(in): factor limiting transpiration in the aquifer (-)
                              iLayerThermalC,               & ! intent(in): thermal conductivity at the interface of each layer (W m-1 K-1)
                              mLayerVolHtCapBulk,           & ! intent(in): bulk volumetric heat capacity (J m-3 K-1)
                              mLayerTcrit,                  & ! intent(in): critical soil temperature above which all water is unfrozen (K)
                              ! model diagnostic variables (output)
                              mLayerdTheta_dTk,             & ! intent(out): derivative in the freezing curve (K-1)
                              mLayerInitTranspire,          & ! intent(out): transpiration loss from each soil layer at the start of the step (m s-1)
                              mLayerTranspire,              & ! intent(out): transpiration loss from each soil layer (m s-1)
                              iLayerInitNrgFlux,            & ! intent(out): energy flux at layer interfaces at the start of the time step (W m-2)
                              iLayerNrgFlux,                & ! intent(out): energy flux at layer interfaces at the end of the time step (W m-2)
                              ! diagnostic scalar variables (output)
                              scalarInitAquiferTranspire,   & ! intent(out): transpiration loss from the aquifer at the start-of-step (m s-1)
                              scalarAquiferTranspire,       & ! intent(out): transpiration loss from the aquifer at the end-of-step (m s-1)
                              ! output variables from heatTransf subroutine
                              mLayerTempDiff,               & ! intent(out): iteration increment for temperature (K)
                              scalarVegetationTempNew,      & ! intent(out): new vegetation temperature (K)
                              mLayerTempNew,                & ! intent(out): new temperature (K)
                              mLayerVolFracIceNew,          & ! intent(out): new volumetric fraction of ice (-)
                              mLayerVolFracLiqNew,          & ! intent(out): new volumetric fraction of liquid water (-)
                              mLayerMatricHeadNew,          & ! intent(out): new matric head (m)
                              err,message)                    ! intent(out): error control
 ! utility modules
 USE phseChange_module,only:phseChange                        ! compute change in phase over the time step
 USE snow_utils_module,only:dFracLiq_dTk                      ! differentiate the freezing curve w.r.t. temperature (snow)
 USE soil_utils_module,only:dTheta_dTk                        ! differentiate the freezing curve w.r.t. temperature (soil)
 USE conv_funcs_module,only:relhm2sphm                        ! compute specific humidity 
 USE tridagSolv_module,only:tridag                            ! solve tridiagonal system of equations
 implicit none
 ! input variables from the heatTransf subroutine
 real(dp),intent(in)            :: dt                         ! time step (seconds)
 integer(i4b),intent(in)        :: iter                       ! iteration count
 real(dp),intent(in)            :: scalarVegetationTempIter   ! trial vegetation temperature (K)
 real(dp),intent(in)            :: mLayerTempIter(:)          ! trial temperature at the current iteration (K)
 real(dp),intent(in)            :: mLayerVolFracIceIter(:)    ! volumetric fraction of ice at the current iteration (-)
 real(dp),intent(in)            :: mLayerVolFracLiqIter(:)    ! volumetric fraction of liquid water at the current iteration (-)
 real(dp),intent(in)            :: mLayerMatricHeadIter(:)    ! matric head at the current iteration (m)
 ! model decisions
 integer(i4b),intent(in)        :: num_method                 ! choice of numerical method
 integer(i4b),intent(in)        :: fDerivMeth                 ! method used to calculate flux derivatives
 integer(i4b),intent(in)        :: bcUpprTdyn                 ! type of upper boundary condition for thermodynamics
 integer(i4b),intent(in)        :: bcLowrTdyn                 ! type of lower boundary condition for thermodynamics
 integer(i4b),intent(in)        :: bcUpprSoiH                 ! type of upper boundary condition for soil hydrology
 integer(i4b),intent(in)        :: ixGroundwater              ! choice of groundwater parameterization
 ! model index variables
 integer(i4b),intent(in)        :: nLayers                    ! number of layers
 integer(i4b),intent(in)        :: layerType(:)               ! type of the layer (ix_soil or ix_snow)
 ! general model parameters
 real(dp),intent(in)            :: mHeight                    ! measurement height (m)
 real(dp),intent(in)            :: wimplicit                  ! weight assigned to start-of-step fluxes (-)
 real(dp),intent(in)            :: snowfrz_scale              ! scaling parameter for the snow freezing curve (K-1)
 real(dp),intent(in)            :: lowerBoundTemp             ! temperature of the lower boundary (K)
 ! soil parameters
 real(dp),intent(in)            :: vGn_alpha                  ! van Genutchen "alpha" parameter
 real(dp),intent(in)            :: vGn_n                      ! van Genutchen "n" parameter
 real(dp),intent(in)            :: theta_sat                  ! soil porosity (-)
 real(dp),intent(in)            :: theta_res                  ! soil residual volumetric water content (-)
 ! derived model variables that are constant over the simulation period
 real(dp),intent(in)            :: vGn_m                      ! van Genutchen "m" parameter (-)
 real(dp),intent(in)            :: mLayerRootDensity(:)       ! root density in each layer (-)
 real(dp),intent(in)            :: scalarAquiferRootFrac      ! fraction of roots below the lowest unsaturated layer (-) 
 ! model forcing data
 real(dp),intent(in)            :: sw_down                    ! downward shortwave radiation (W m-2)
 real(dp),intent(in)            :: lw_down                    ! downward longwave radiation (W m-2)
 real(dp),intent(in)            :: airtemp                    ! air temperature at 2 meter height (K)
 real(dp),intent(in)            :: windspd                    ! wind speed at 10 meter height (m s-1)
 real(dp),intent(in)            :: airpres                    ! air pressure at 2 meter height (Pa)
 real(dp),intent(in)            :: spechum                    ! specific humidity at 2 meter height (g g-1)
 ! model state variables
 real(dp),intent(in)            :: scalarAlbedo               ! surface albedo (-)
 real(dp),intent(in)            :: mLayerTemp(:)              ! temperature of each layer (K)
 real(dp),intent(in)            :: mLayerVolFracIce(:)        ! volumetric fraction of ice in each layer (-)
 ! model coordinate variables (intent in)
 real(dp),intent(in)            :: mLayerDepth(:)             ! depth of each layer (m)
 real(dp),intent(in)            :: mLayerHeight(:)            ! height at the mid-point of each layer (m)
 real(dp),intent(in)            :: iLayerHeight(0:)           ! height at the interface of each layer (m)
 ! model diagnostic variables (intent in)
 real(dp),intent(in)            :: spectralIncomingDirect(:)  ! downwelling direct shortwave radiation for all wave bands (W m-2)
 real(dp),intent(in)            :: spectralIncomingDiffuse(:) ! downwelling diffuse shortwave radiation for all wave bands (W m-2)
 real(dp),intent(in)            :: scalarTranspireLim         ! aggregate soil moist & veg limit on transpiration, weighted by root density (-)
 real(dp),intent(in)            :: mLayerTranspireLim(:)      ! moisture avail factor limiting transpiration in each layer (-)
 real(dp),intent(in)            :: scalarTranspireLimAqfr     ! factor limiting transpiration in the aquifer (-)
 real(dp),intent(in)            :: mLayerVolHtCapBulk(:)      ! bulk volumetric heat capacity (J m-3 K-1)
 real(dp),intent(in)            :: iLayerThermalC(0:)         ! thermal conductivity at the interface of each layer (W m-1 K-1)
 real(dp),intent(in)            :: mLayerTcrit(:)             ! critical soil temperature above which all water is unfrozen (K)
 ! model diagnostic variables (intent out)
 real(dp),intent(out)           :: mLayerdTheta_dTk(:)        ! derivative in the freezing curve (K-1)
 real(dp),intent(out)           :: mLayerInitTranspire(:)     ! transpiration loss from each soil layer at the start of the step (m s-1)
 real(dp),intent(out)           :: mLayerTranspire(:)         ! transpiration loss from each soil layer (m s-1)
 real(dp),intent(out)           :: iLayerInitNrgFlux(0:)      ! energy flux at layer interfaces at the start of the time step (W m-2)
 real(dp),intent(out)           :: iLayerNrgFlux(0:)          ! energy flux at layer interfaces at the end of the time step (W m-2)
 ! diagnostic scalar variables
 real(dp),intent(out)           :: scalarInitAquiferTranspire ! transpiration loss from the aquifer at the start-of-step (m s-1)
 real(dp),intent(out)           :: scalarAquiferTranspire     ! transpiration loss from the aquifer at the end-of-step (m s-1)
 ! output variables from the heatTransf subroutine
 real(dp),intent(out)           :: mLayerTempDiff(:)          ! iteration increment for temperature (K) 
 real(dp),intent(out)           :: scalarVegetationTempNew    ! new vegetation temperature (K)
 real(dp),intent(out)           :: mLayerTempNew(:)           ! new temperature (K)
 real(dp),intent(out)           :: mLayerVolFracIceNew(:)     ! new volumetric fraction of ice (-)
 real(dp),intent(out)           :: mLayerVolFracLiqNew(:)     ! new volumetric fraction of liquid water (-)
 real(dp),intent(out)           :: mLayerMatricHeadNew(:)     ! new matric head (m)
 integer(i4b),intent(out)       :: err                        ! error code
 character(*),intent(out)       :: message                    ! error message
 ! ---------------------------------------------------------------------------------------------------------------------------------
 ! define local variables
 ! ---------------------------------------------------------------------------------------------------------------------------------
 ! define general local variables
 character(LEN=256)             :: cmessage                   ! error message of downwind routine
 integer(i4b)                   :: iLayer                     ! index of model layers
 logical(lgt)                   :: printflag                  ! .true. if print progress to the screen
 logical(lgt)                   :: fTranspire                 ! .true. if computing transpiration
 real(dp)                       :: theta                      ! total volumetric water content (liquid plus ice)
 real(dp)                       :: critDiff                   ! temperature difference from critical temperature (K)
 real(dp)                       :: maxdiffTemp(1)             ! maximum difference between temperature input and start-of-step temperature (K)
 real(dp),parameter             :: epsT=1.d-10                ! offset from Tcrit when re-setting iterations at the critical temperature (K)
 integer(i4b)                   :: nUnsat                     ! number of unsaturated layers
 ! define the local variables for the solution
 real(dp)                       :: totalSurfaceFlux           ! total surface flux (W m-2)
 real(dp)                       :: dTotalSurfaceFlux_dTemp    ! derivative in total surface flux w.r.t. temperature (W m-2 K-1)
 real(dp),dimension(0:size(mLayerTempIter)) :: dFlux_dTempAbove ! derivative in flux w.r.t. temperature in the layer above (J m-2 s-1 K-1)
 real(dp),dimension(0:size(mLayerTempIter)) :: dFlux_dTempBelow ! derivative in flux w.r.t. temperature in the layer below (J m-2 s-1 K-1)
 real(dp)                       :: nrg0,nrg1                  ! energy content at the start of the time step / current iteration (J m-3)
 real(dp)                       :: flx0,flx1                  ! fluxes at the start of the time step / current iteration (J m-3)
 real(dp)                       :: phse                       ! phase change term (J m-3)
 real(dp),dimension(size(mLayerTempIter))   :: rvec           ! residual vector (J m-3)
 real(dp)                                   :: wtim           ! weighted time (s-1)
 real(dp),dimension(size(mLayerTempIter)-1) :: d_m1           ! sub-diagonal elements of the tridiagonal system (J m-3 K-1)
 real(dp),dimension(size(mLayerTempIter))   :: diag           ! diagonal elements of the tridiagonal system (J m-3 K-1)
 real(dp),dimension(size(mLayerTempIter)-1) :: d_p1           ! super-diagonal elements of the tridiagonal system (J m-3 K-1)
 ! define the local variables for the line search
 real(dp),dimension(size(mLayerTempIter))   :: g             ! gradient of the function vector (J m-3 J m-3 K-1)
 real(dp)                                   :: fold,fnew     ! function values (J m-3 J m-3)
 real(dp),parameter            :: STPMX=5._dp                ! maximum step size in line search (K)
 real(dp)                      :: stpmax                     ! scaled maximum step size
 logical(lgt)                  :: crossFlag                  ! .true. if temperature crosses the critical temperature
 ! ---------------------------------------------------------------------------------------------------------------------------------
 ! initialize error control
 err=0; message="heatTransf_muster/"

 ! initialize print flag
 printflag=.false.

 if(bcUpprSoiH==prescribedHead .or. nSnow>0)then
  fTranspire=.false.
 else
  fTranspire=.true.
 endif

 ! iterate on the surface temperatire
 if(num_method==iterSurfEnergyBal)then
  err=20; message=trim(message)//'option "iterSurfEnergyBal" not implemented yet';return
 endif

 ! ***** compute fluxes at layer interfaces and their derivatives (J m-2 s-1)
 call iLayer_nrg(&
                 ! (model control variables)
                 fDerivMeth,             & ! intent(in): method used to compute derivatives (numerical or analytical)
                 ! (input)
                 mLayerDepth,            & ! intent(in): depth of each layer (m)
                 mLayerHeight,           & ! intent(in): height of layer mid-points (m)
                 iLayerThermalC,         & ! intent(in): thermal conductivity at layer interfaces (W m-1)
                 mLayerTempIter,         & ! intent(in): trial temperature at the current iteration (K)
                 totalSurfaceFlux,       & ! intent(in): total flux at the surface (W m-2)
                 dTotalSurfaceFlux_dTemp,& ! intent(in): derivative in total surface flux w.r.t. temperature (W m-2 K-1)
                 lowerBoundTemp,         & ! intent(in): temperature of the lower boundary (K)
                 ! (output)
                 iLayerNrgFlux,          & ! intent(out): energy flux at the layer interfaces (W m-2)
                 dFlux_dTempAbove,       & ! intent(out): derivatives in the flux w.r.t. temperature in the layer above (W m-2 K-1)
                 dFlux_dTempBelow,       & ! intent(out): derivatives in the flux w.r.t. temperature in the layer below (W m-2 K-1)
                 err,cmessage)             ! intent(out): error control
 if(err/=0)then; message=trim(message)//trim(cmessage); return; endif

 ! ***** assign initial fluxes
 if(iter==1)then
  ! check that the temperature matches the temperature at the start of the step
  maxdiffTemp = maxval(abs(mLayerTempIter - mLayerTemp))
  if(maxdiffTemp(1) > 1.d-8)then; err=20; message=trim(message)//'first guess for temperature must match start-of-step value'; return; endif
  ! assign initial fluxes
  iLayerInitNrgFlux = iLayerNrgFlux
  ! compute transpiration for each layer at the start of the time step (m s-1)
  !scalarPotentialET = 0._dp !iden_air * windspd * scalarExCoef * (spechum - relhm2sphm(RHsurf,airpres,mLayerTemp(1))) ! kg m-2 s-1
  if(fTranspire)then
   mLayerInitTranspire(1:nSoil) = 0._dp !(mLayerTranspireLim(1:nSoil)*mLayerRootDensity(1:nSoil)*scalarPotentialET)/iden_water
   scalarInitAquiferTranspire   = 0._dp ! (scalarTranspireLimAqfr*scalarAquiferRootFrac*scalarPotentialET)/iden_water
  else
   mLayerInitTranspire(1:nSoil) = 0._dp
   scalarInitAquiferTranspire   = 0._dp
  endif
 endif

 ! ***** compute the residual vector (J m-3)
 do iLayer=1,nLayers
  ! (compute individual terms)
  nrg0 = mLayerVolHtCapBulk(iLayer)*mLayerTemp(iLayer)      ! energy content at the start of the time step (J m-3)
  nrg1 = mLayerVolHtCapBulk(iLayer)*mLayerTempIter(iLayer)  ! energy content at the current iteration (J m-3)
  flx0 = -(iLayerInitNrgFlux(iLayer) - iLayerInitNrgFlux(iLayer-1))*(dt/mLayerDepth(iLayer))  ! flux at the start of the time step (J m-3)
  flx1 = -(iLayerNrgFlux(iLayer) - iLayerNrgFlux(iLayer-1))*(dt/mLayerDepth(iLayer))          ! flux at the current iteration (J m-3)
  phse = LH_fus*iden_ice*(mLayerVolFracIceIter(iLayer) - mLayerVolFracIce(iLayer))   ! phase change term (J m-3)
  ! (compute residuals)
  rvec(iLayer) = nrg1 - (nrg0 + flx0*wimplicit + flx1*(1._dp - wimplicit) + phse)
  ! (print progress)
  !if(iLayer < 5) write(*,'(a,1x,i4,1x,f9.3,1x,10(e20.10,1x))') 'residuals = ', iLayer, mLayerTempIter(iLayer), rvec(iLayer), nrg0, nrg1, (nrg1 - nrg0), flx0, flx1, phse
 end do

 ! ***** compute the derivative in the freezing curve w.r.t. temperature (K-1)
 do iLayer=1,nLayers
  select case(layerType(iLayer))
   case(ix_snow) ! (snow layers)
    theta = mLayerVolFracIceIter(iLayer)*(iden_ice/iden_water) + mLayerVolFracLiqIter(iLayer)
    mLayerdTheta_dTk(iLayer) = dFracLiq_dTk(mLayerTempIter(iLayer),snowfrz_scale)*theta
    !if(iLayer < 10) write(*,'(a,1x,i4,1x,e20.10,1x,3(f10.5,1x))') 'iLayer, mLayerVolHtCapBulk(iLayer), mLayerdTheta_dTk(iLayer), snowfrz_scale, mLayerTempIter(iLayer) = ', &
    !                                                               iLayer, mLayerVolHtCapBulk(iLayer), mLayerdTheta_dTk(iLayer), snowfrz_scale, mLayerTempIter(iLayer)
   case(ix_soil) ! (soil layers)
    if(mLayerVolFracIceIter(iLayer)>0._dp)then
     mLayerdTheta_dTk(iLayer) = dTheta_dTk(mLayerTempIter(iLayer),theta_res,theta_sat,vGn_alpha,vGn_n,vGn_m)
    else
     mLayerdTheta_dTk(iLayer) = 0._dp
    endif
   case default
    err=40; message=trim(message)//"cannot identify the layer as snow or soil"; return
  endselect
 end do

 ! ***** assemble the tri-diagonal matrix
 wtim = (1._dp - wimplicit)*dt  ! weighted time
 diag = (wtim/mLayerDepth)*(-dFlux_dTempBelow(0:nLayers-1) + dFlux_dTempAbove(1:nLayers)) + mLayerdTheta_dTk*LH_fus*iden_water + mLayerVolHtCapBulk
 d_m1 = (wtim/mLayerDepth(1:nLayers-1))*(-dFlux_dTempAbove(1:nLayers-1) )
 d_p1 = (wtim/mLayerDepth(1:nLayers-1))*( dFlux_dTempBelow(1:nLayers-1) )

 ! ***** solve the tridiagonal system of equations -- returns mLayerTempDiff
 call tridag(d_m1,                    & ! intent(in): sub-diagonal elements of the tridiagonal system (J m-3 K-1)
             diag,                    & ! intent(in): diagonal elements of the tridiagonal system (J m-3 K-1)
             d_p1,                    & ! intent(in): super-diagonal elements of the tridiagonal system (J m-3 K-1)
             -rvec,                   & ! intent(in): residual vector (J m-3)
             mLayerTempDiff,          & ! intent(out): temperature increment (K)
             err,cmessage)              ! intent(out): error control
 if(err/=0)then; message=trim(message)//trim(cmessage); return; endif
 !write(*,'(a,1x,10(f15.8,1x))') 'mLayerTempDiff = ', mLayerTempDiff
 !pause 'after solve'

 ! check for oscillations (borrowed from the SHAW model)
 !if(iter > 10)then
 ! ! if delta is jumping between positive and negative, then cut the delta in half
 ! do iLayer=1,nLayers
 !  ! (case of oscillatory behavior)
 !  if(mLayerTempDiff(iLayer)*mLayerTempDiffOld(iLayer) < 0._dp)then
 !   mLayerTempDiff(iLayer) = mLayerTempDiff(iLayer)/2._dp
 !   !message=trim(message)//'check fix to oscillatory behavior'
 !   !err=20; return
 !  endif  ! (if there is an oscillation)
 ! end do
 !endif

 ! adjust del temperature in cases where snow temperature exceeds Tfreeze -- use bi-section
 if(nSnow>0)then
  do iLayer=1,nSnow
   if(mLayerTempIter(iLayer)+mLayerTempDiff(iLayer) > Tfreeze)then
    mLayerTempDiff(iLayer) = (Tfreeze-mLayerTempIter(iLayer))*0.5_dp
   endif
  end do
 endif

 ! initialize the flag to define when temperature crosses the freezing point
 crossFlag=.false.

 ! adjust del temperature in cases where soil temperature crosses the critical temperature
 do iLayer=nSnow+1,nLayers
  ! get the difference from the critical temperature (K)
  critDiff = mLayerTcrit(iLayer-nSnow) - mLayerTempIter(iLayer)
  ! set temperature to Tcrit in cases where temperatures cross Tcrit
  if(critDiff > 0._dp)then  ! (mLayerTempIter < Tcrit)
   if(mLayerTempDiff(iLayer) > critDiff)then; mLayerTempDiff(iLayer) = critDiff + epsT; crossFlag=.true.; endif
  else                      ! (mLayerTempIter > Tcrit)
   if(mLayerTempDiff(iLayer) < critDiff)then; mLayerTempDiff(iLayer) = critDiff - epsT; crossFlag=.true.; endif
  endif
 end do

 ! update temperature and compute phase change if the soil temperature crosses the critical temperature
 if(crossFlag .or. num_method==nonIterative)then

  ! update temperature
  mLayerTempNew = mLayerTempIter + mLayerTempDiff
  ! compute phase change
  call phsechange(mLayerTempNew,       & ! intent(in): new temperature vector (K)
                  mLayerMatricHeadIter,& ! intent(in): matric head at the current iteration (m)
                  mLayerVolFracLiqIter,& ! intent(in): volumetric fraction of liquid water at the current iteration (-)
                  mLayerVolFracIceIter,& ! intent(in): volumetric fraction of ice at the current iteration (-)
                  mLayerMatricHeadNew, & ! intent(out): new matric head (m)
                  mLayerVolFracLiqNew, & ! intent(out): new volumetric fraction of liquid water (-)
                  mLayerVolFracIceNew, & ! intent(out): new volumetric fraction of ice (-)
                  err,cmessage)          ! intent(out): error control
  if(err/=0)then; message=trim(message)//trim(cmessage); return; endif

 ! otherwise, conduct a line search
 else

  ! compute the gradient of the function vector (J m-3 J m-3 K-1)
  do iLayer=1,nLayers
   if(iLayer==1)then;           g(iLayer) =                                 diag(iLayer)*rvec(iLayer) + d_p1(iLayer)*rvec(iLayer+1)
   elseif(iLayer==nLayers)then; g(iLayer) = d_m1(iLayer-1)*rvec(iLayer-1) + diag(iLayer)*rvec(iLayer)
   else;                        g(iLayer) = d_m1(iLayer-1)*rvec(iLayer-1) + diag(iLayer)*rvec(iLayer) + d_p1(iLayer)*rvec(iLayer+1)
   endif
  end do

  ! compute the function value (J m-3 J m-3)
  fold = 0.5_dp*dot_product(rvec,rvec)

  ! compute maximum step size (K)
  stpmax=STPMX*real(nLayers,dp)
  !stpmax=STPMX*max(sqrt(dot_product(mLayerTempIter,mLayerTempIter)),real(nLayers,dp))

  ! conduct the line search
  call lnsrch(&
              ! (model control variables)
              dt,                      & ! intent(in): time step (seconds)
              fDerivMeth,              & ! intent(in): method used to compute derivatives (numerical or analytical)
              ixGroundwater,           & ! intent(in): choice of groundwater representation
              ! (model forcing variables)
              airtemp,                 & ! intent(in): air temperature (K)
              spechum,                 & ! intent(in): specific humidity (g g-1)
              windspd,                 & ! intent(in): wind speed (m s-1)
              airpres,                 & ! intent(in): air pressure (Pa)
              sw_down,                 & ! intent(in): downwelling shortwave radiation (W m-2)   
              lw_down,                 & ! intent(in): downwelling long wave radiation (W m-2)   
              lowerBoundTemp,          & ! intent(in): temperature of the lower boundary (K)
              ! (model parameters)
              mHeight,                 & ! intent(in): measurement height (m)
              wimplicit,               & ! intent(in): weight assigned to start-of-step values (-)
              ! (coordinate variables)
              mLayerDepth,             & ! intent(in): depth of each layer (m)
              mLayerHeight,            & ! intent(in): height of layer mid-points (m)
              iLayerHeight,            & ! intent(in): height of layer interfaces (m)
              ! (diagnostic variables)
              scalarTranspireLim,      & ! intent(in): aggregate soil moist & veg limit on transpiration, weighted by root density (-)
              iLayerThermalC,          & ! intent(in): thermal conductivity at layer interfaces (W m-1)
              mLayerVolHtCapBulk,      & ! intent(in): volumetric heat capacity in each layer (J m-3 K-1)
              iLayerInitNrgFlux,       & ! intent(in): energy flux at layer interfaces at the start of the step (W m-2)
              ! (state variables at start of step)
              scalarAlbedo,            & ! intent(in): surface albedo (-)
              mLayerTemp,              & ! intent(in): temperature in all layers (K)
              mLayerVolFracIce,        & ! intent(in): volumetric fraction of ice in all layers (-)
              ! (trial state variables)
              mLayerTempIter,          & ! intent(in): trial temperature vector (K)
              mLayerMatricHeadIter,    & ! intent(in): matric head at the current iteration (m)
              mLayerVolFracLiqIter,    & ! intent(in): volumetric fraction of liquid water at the current iteration (-)
              mLayerVolFracIceIter,    & ! intent(in): volumetric fraction of ice at the current iteration (-)
              ! (functions and gradients)
              stpmax,                  & ! intent(in): maximum step size (K)
              fold,                    & ! intent(in): function value for trial temperature vector (J m-3 J m-3)
              g,                       & ! intent(in): gradient of the function vector (J m-3 J m-3 K-1)
              mLayerTempDiff,          & ! intent(inout): iteration increment (K)
              ! output
              mLayerTempNew,           & ! intent(out): new temperature vector (K)
              rvec,                    & ! intent(out): new residual vector (J m-3)
              fnew,                    & ! intent(out): new function value (J m-3 J m-3)
              mLayerMatricHeadNew,     & ! intent(out): new matric head (m)
              mLayerVolFracLiqNew,     & ! intent(out): new volumetric fraction of liquid water (-)
              mLayerVolFracIceNew,     & ! intent(out): new volumetric fraction of ice (-)
              err,cmessage)              ! intent(out): error control
  ! negative error code requires convergence check (done in upwind routine), so just check positive errors
  if(err>0)then; message=trim(message)//trim(cmessage); return; endif

 endif  ! (toggle between line search)

 ! ***** update the fluxes at the layer interfaces
 do iLayer=0,nLayers
  if(iLayer==0)then;           iLayerNrgFlux(iLayer) = iLayerNrgFlux(iLayer) + dFlux_dTempBelow(iLayer)*mLayerTempDiff(iLayer+1)
  elseif(iLayer==nLayers)then; iLayerNrgFlux(iLayer) = iLayerNrgFlux(iLayer) + dFlux_dTempAbove(iLayer)*mLayerTempDiff(iLayer)
  else;                        iLayerNrgFlux(iLayer) = iLayerNrgFlux(iLayer) + dFlux_dTempAbove(iLayer)*mLayerTempDiff(iLayer) &
                                                                             + dFlux_dTempBelow(iLayer)*mLayerTempDiff(iLayer+1)
  endif
 end do ! (looping through layers)

 ! ***** compute un-stressed ET (kg m-2 s-1)
 ! NOTE: this is only used for the end-of-step values (start-of-step values defined above)
 !scalarPotentialET = iden_air * windspd * scalarExCoef * (spechum - relhm2sphm(RHsurf,airpres,mLayerTempNew(1)))

 ! ***** compute transpiration (m s-1)  -- NOTE: this includes transpiration from the aquifer (this is OK)
 if(fTranspire)then
  ! ** compute actual transpiration from each soil layer, and the aquifer (m s-1)
  mLayerTranspire(1:nSoil) = 0._dp ! (mLayerTranspireLim(1:nSoil)*mLayerRootDensity(1:nSoil)*scalarPotentialET)/iden_water
  scalarAquiferTranspire   = 0._dp ! (scalarTranspireLimAqfr*scalarAquiferRootFrac*scalarPotentialET)/iden_water
  ! ** compute total transpiration (kg m-2 s-1)
  !scalarMassLiquid = 0._dp !( wimplicit*sum(mLayerInitTranspire)   + (1._dp - wimplicit)*sum(mLayerTranspire)    )*iden_water + &
                           !( wimplicit*scalarInitAquiferTranspire + (1._dp - wimplicit)*scalarAquiferTranspire  )*iden_water
  !print*, 'dt*mLayerTranspire(1:5)/mLayerDepth(1:5) = ', dt*mLayerTranspire(1:5)/mLayerDepth(1:5) 
 else
  mLayerTranspire(1:nSoil) = 0._dp
  scalarAquiferTranspire   = 0._dp
  !scalarMassLiquid         = 0._dp
 endif

 ! ***** compute sublimation/frost (kg m-2 s-1)
 !if(nSnow==0) scalarMassSolid  = 0._dp
 !if(nsnow >0) scalarMassSolid  = 0._dp !scalarPotentialET

 ! update sensible and latent heat (W m-2) --> positive downwards
 !scalarSenHeat = scalarExCoef * scalarExSen*(airtemp - mLayerTempNew(1))
 !if(nSnow==0) scalarLatHeat = scalarMassLiquid*LH_vap
 !if(nsnow >0) scalarLatHeat = scalarMassSolid*LH_sub

 ! ====================================================================================================================

 end subroutine heatTransf_muster


 ! ************************************************************************************************
 ! private subroutine: compute energy fluxes at layer interfaces, and their derivatives
 ! ************************************************************************************************
 subroutine iLayer_nrg(&
                       ! (model control variables)
                       fDerivMeth,             & ! intent(in): method used to compute derivatives (numerical or analytical)
                       ! (input)
                       mLayerDepth,            & ! intent(in): depth of each layer (m)
                       mLayerHeight,           & ! intent(in): height of layer mid-points (m)
                       iLayerThermalC,         & ! intent(in): thermal conductivity at layer interfaces (W m-1)
                       mLayerTempTrial,        & ! intent(in): trial temperature at the current iteration (K)
                       totalSurfaceFlux,       & ! intent(in): total flux at the surface (W m-2)
                       dTotalSurfaceFlux_dTemp,& ! intent(in): derivative in total surface flux w.r.t. temperature (W m-2 K-1)
                       lowerBoundTemp,         & ! intent(in): temperature of the lower boundary (K)
                       ! (output)
                       iLayerNrgFlux,          & ! intent(out): energy flux at the layer interfaces (W m-2)
                       dFlux_dTempAbove,       & ! intent(out): derivatives in the flux w.r.t. temperature in the layer above (W m-2 K-1)
                       dFlux_dTempBelow,       & ! intent(out): derivatives in the flux w.r.t. temperature in the layer below (W m-2 K-1)
                       err,message)              ! intent(out): error control
 ! compute derivative in fluxes at layer interfaces w.r.t. temperature in the layer above and the layer below
 implicit none
 ! input
 integer(i4b),intent(in)       :: fDerivMeth               ! intent(in): method used to calculate derivatives
 real(dp),intent(in)           :: mLayerDepth(:)           ! intent(in): depth of each layer (m)
 real(dp),intent(in)           :: mLayerHeight(:)          ! intent(in): height of layer mid-points (m)
 real(dp),intent(in)           :: iLayerThermalC(0:)       ! thermal conductivity at layer interfaces (W m-1)
 real(dp),intent(in)           :: mLayerTempTrial(:)       ! trial temperature at the current iteration (K)
 real(dp),intent(in)           :: totalSurfaceFlux         ! total surface flux (W m-2)
 real(dp),intent(in)           :: dTotalSurfaceFlux_dTemp  ! derivative in total surface flux w.r.t. temperature (W m-2 K-1)
 real(dp),intent(in)           :: lowerBoundTemp           ! temperature of the lower boundary (K)
 ! output
 real(dp),intent(out)          :: iLayerNrgFlux(0:)        ! energy flux at the layer interfaces (W m-2)
 real(dp),intent(out)          :: dFlux_dTempAbove(0:)     ! derivatives in the flux w.r.t. temperature in the layer above (J m-2 s-1 K-1)
 real(dp),intent(out)          :: dFlux_dTempBelow(0:)     ! derivatives in the flux w.r.t. temperature in the layer below (J m-2 s-1 K-1)
 integer(i4b),intent(out)      :: err                      ! error code
 character(*),intent(out)      :: message                  ! error message
 ! local variables
 integer(i4b)                  :: iLayer                   ! index of model layers
 real(dp),parameter            :: dx=1.e-8_dp              ! finite difference increment (K)
 real(dp)                      :: dz                       ! height difference (m)
 real(dp)                      :: flux0,flux1,flux2        ! fluxes used to calculate derivatives (W m-2)
 ! initialize error control
 err=0; message='iLayer_nrg/'

 ! -------------------------------------------------------------------------------------------------------------------------
 ! ***** compute the fluxes at layer interfaces *****
 ! -------------------------------------------------------------------------------------------------------------------------
 ! compute fluxes within the domain -- positive downwards
 do iLayer=0,nLayers
  ! compute flux at the upper boundary -- positive downwards
  if(iLayer==0)then;           iLayerNrgFlux(0)       = totalSurfaceFlux
  ! compute fluxes at the lower boundary -- positive downwards
  elseif(iLayer==nLayers)then; iLayerNrgFlux(nLayers) = -iLayerThermalC(iLayer)*(lowerBoundTemp - mLayerTempTrial(iLayer))/(mLayerDepth(iLayer)*0.5_dp)
  ! compute fluxes within the domain -- positive downwards
  else;                        iLayerNrgFlux(iLayer)  = -iLayerThermalC(iLayer)*(mLayerTempTrial(iLayer+1) - mLayerTempTrial(iLayer)) / &
                                                                                (mLayerHeight(iLayer+1) - mLayerHeight(iLayer))
  endif ! (the type of layer)
  ! print progress
  !if(iLayer < 10) write(*,'(a,1x,i4,1x,10(f10.5,1x))') trim(message)//'iLayer, iLayerThermalC(iLayer), iLayerNrgFlux(iLayer), mLayerTempTrial(iLayer:iLayer+1) = ', &
  !                                                                     iLayer, iLayerThermalC(iLayer), iLayerNrgFlux(iLayer), mLayerTempTrial(iLayer:iLayer+1)
 end do
 ! -------------------------------------------------------------------------------------------------------------------------
 ! ***** compute the derivative in fluxes at layer interfaces w.r.t temperature in the layer above and the layer below *****
 ! -------------------------------------------------------------------------------------------------------------------------

 ! initialize un-used elements
 dFlux_dTempAbove(0)       = -huge(lowerBoundTemp)  ! don't expect this to be used, so deliberately set to a ridiculous value to cause problems
 dFlux_dTempBelow(nLayers) = -huge(lowerBoundTemp)  ! don't expect this to be used, so deliberately set to a ridiculous value to cause problems

 ! loop through INTERFACES...
 do iLayer=0,nLayers

  ! ***** the upper boundary -- ** NOTE: dTotalSurfaceFlux_dTemp was computed previously using fDerivMeth
  if(iLayer==0)then  ! (upper boundary)
   dFlux_dTempBelow(iLayer) = dTotalSurfaceFlux_dTemp

  ! ***** the lower boundary
  elseif(iLayer==nLayers)then  ! (lower boundary)
   dz = mLayerDepth(iLayer)*0.5_dp
   if(fDerivMeth==analytical)then    ! ** analytical derivatives
    dFlux_dTempAbove(iLayer) = iLayerThermalC(iLayer)/dz
   else                              ! ** numerical derivatives
    flux0 = -iLayerThermalC(iLayer)*(lowerBoundTemp - (mLayerTempTrial(iLayer)   ))/dz
    flux1 = -iLayerThermalC(iLayer)*(lowerBoundTemp - (mLayerTempTrial(iLayer)+dx))/dz
    dFlux_dTempAbove(iLayer) = (flux1 - flux0)/dx
   endif

  ! ***** internal layers
  else
   dz = (mLayerHeight(iLayer+1) - mLayerHeight(iLayer))
   if(fDerivMeth==analytical)then    ! ** analytical derivatives
    dFlux_dTempAbove(iLayer) =  iLayerThermalC(iLayer)/dz
    dFlux_dTempBelow(iLayer) = -iLayerThermalC(iLayer)/dz
   else                              ! ** numerical derivatives
    flux0 = -iLayerThermalC(iLayer)*( mLayerTempTrial(iLayer+1)     -  mLayerTempTrial(iLayer)    ) / dz
    flux1 = -iLayerThermalC(iLayer)*( mLayerTempTrial(iLayer+1)     - (mLayerTempTrial(iLayer)+dx)) / dz
    flux2 = -iLayerThermalC(iLayer)*((mLayerTempTrial(iLayer+1)+dx) -  mLayerTempTrial(iLayer)    ) / dz
    dFlux_dTempAbove(iLayer) = (flux1 - flux0)/dx
    dFlux_dTempBelow(iLayer) = (flux2 - flux0)/dx
   endif

  endif  ! type of layer (upper, internal, or lower)

  !if(iLayer < 5) &
  ! write(*,'(2(i4,1x),2(e20.10,1x))') fDerivMeth, iLayer, dFlux_dTempAbove(iLayer), dFlux_dTempBelow(iLayer)

 end do  ! (looping through layers)

 end subroutine iLayer_nrg


 ! ************************************************************************************************
 ! private subroutine: compute the residual vector
 ! ************************************************************************************************
 subroutine nrg_residl(&
                       ! (model control variables)
                       dt,                       & ! intent(in): time step (seconds)
                       fDerivMeth,               & ! intent(in): method used to compute derivatives (numerical or analytical)
                       ixGroundwater,            & ! intent(in): choice of groundwater representation
                       ! (model forcing variables)
                       airtemp,                  & ! intent(in): air temperature (K)
                       spechum,                  & ! intent(in): specific humidity (g g-1)
                       windspd,                  & ! intent(in): wind speed (m s-1)
                       airpres,                  & ! intent(in): air pressure (Pa)
                       sw_down,                  & ! intent(in): downwelling shortwave radiation (W m-2)   
                       lw_down,                  & ! intent(in): downwelling long wave radiation (W m-2)   
                       lowerBoundTemp,           & ! intent(in): temperature of the lower boundary (K)
                       ! (model parameters)
                       mHeight,                  & ! intent(in): measurement height (m)
                       wimplicit,                & ! intent(in): weight assigned to start-of-step values (-)
                       ! (coordinate variables)
                       mLayerDepth,              & ! intent(in): depth of each layer (m)
                       mLayerHeight,             & ! intent(in): height of layer mid-points (m)
                       iLayerHeight,             & ! intent(in): height of layer interfaces (m)
                       ! (diagnostic variables)
                       scalarTranspireLim,       & ! intent(in): aggregate soil moist & veg limit on transpiration, weighted by root density (-)
                       iLayerThermalC,           & ! intent(in): thermal conductivity at layer interfaces (W m-1)
                       mLayerVolHtCapBulk,       & ! intent(in): volumetric heat capacity in each layer (J m-3)
                       iLayerInitNrgFlux,        & ! intent(in): energy flux at layer interfaces at the start of the step (W m-2)
                       ! (state variables at start of step))
                       scalarAlbedo,             & ! intent(in): surface albedo (-)
                       mLayerTemp,               & ! intent(in): temperature in all layers (K)
                       mLayerVolFracIce,         & ! intent(in): volumetric fraction of ice in all layers (-)
                       ! (trial state variables)
                       mLayerTempTrial,          & ! intent(in): trial temperature in all layers at the current iteration (K)
                       mLayerVolFracIceTrial,    & ! intent(in): trial volumetric fraction of ice in all layers at the current iteration (-)
                       mLayerMatricHeadTrial,    & ! intent(in): trial matric head in all layers at the current iteration (m)
                       ! (output)
                       rvec,                     & ! intent(out): residual vector (J m-3)
                       err,message)                ! intent(out): error control
 ! -------------------------------------------------------------------------------------------------------
 implicit none
 ! input (control)
 real(dp),intent(in)           :: dt                        ! intent(in): time step (seconds)
 integer(i4b),intent(in)       :: fDerivMeth                ! intent(in): method used to calculate derivatives
 integer(i4b),intent(in)       :: ixGroundwater             ! intent(in): choice of groundwater representation
 ! input (forcing)
 real(dp),intent(in)           :: airtemp                   ! intent(in): air temperature (K)
 real(dp),intent(in)           :: spechum                   ! intent(in): specific humidity (g g-1)
 real(dp),intent(in)           :: windspd                   ! intent(in): wind speed (m s-1)
 real(dp),intent(in)           :: airpres                   ! intent(in): air pressure (Pa)
 real(dp),intent(in)           :: sw_down                   ! intent(in): downwelling shortwave radiation (W m-2)   
 real(dp),intent(in)           :: lw_down                   ! intent(in): downwelling long wave radiation (W m-2)   
 real(dp),intent(in)           :: lowerBoundTemp            ! intent(in): temperature of the lower boundary (K)
 ! input (parameters)
 real(dp),intent(in)           :: mHeight                   ! intent(in): measurement height (m)
 real(dp),intent(in)           :: wimplicit                 ! intent(in): weight assigned to start-of-step values (-)
 ! input (coordinate variables)
 real(dp),intent(in)           :: mLayerDepth(:)            ! intent(in): depth of each layer (m)
 real(dp),intent(in)           :: mLayerHeight(:)           ! intent(in): height of layer mid-points (m)
 real(dp),intent(in)           :: iLayerHeight(0:)          ! intent(in): height of layer interfaces (m)
 ! input (diagnostic variables)
 real(dp),intent(in)           :: scalarTranspireLim        ! intent(in): resistance to evaporation at the surface (-)
 real(dp),intent(in)           :: iLayerThermalC(0:)        ! intent(in): thermal conductivity at layer interfaces (W m-1)
 real(dp),intent(in)           :: mLayerVolHtCapBulk(:)     ! intent(in): volumetric heat capacity in each layer (J m-3)
 real(dp),intent(in)           :: iLayerInitNrgFlux(0:)     ! intent(in): energy flux at layer interfaces at the start of the step (W m-2)
 ! input (state variables)
 real(dp),intent(in)           :: scalarAlbedo              ! intent(in): surface albedo (-)
 real(dp),intent(in)           :: mLayerTemp(:)             ! intent(in): temperature in all layers (K)
 real(dp),intent(in)           :: mLayerVolFracIce(:)       ! intent(in): volumetric fraction of ice in all layers (-)
 ! input (trial state variables)
 real(dp),intent(in)           :: mLayerTempTrial(:)        ! intent(in): trial temperature at the current iteration (K)
 real(dp),intent(in)           :: mLayerVolFracIceTrial(:)  ! intent(in): trial volumetric fraction of ice in all layers at the current iteration (-)
 real(dp),intent(in)           :: mLayerMatricHeadTrial(:)  ! intent(in): matric head at the current iteration (m)
 ! output
 real(dp),intent(out)          :: rvec(:)                   ! intent(out): residual vector (J m-3) 
 integer(i4b),intent(out)      :: err                       ! intent(out): error code
 character(*),intent(out)      :: message                   ! intent(out): error message
 ! -------------------------------------------------------------------------------------------------------
 ! general local variables
 character(LEN=256)            :: cmessage                  ! error message of downwind routine
 integer(i4b)                  :: iLayer                    ! index of model layers
 ! local variables for surface fluxes
 real(dp)                      :: scalarExCoef              ! surface-atmosphere exchange coeffcient (-)
 real(dp)                      :: scalarExSen               ! exchange factor for sensible heat (W m-2 K-1)
 real(dp)                      :: scalarExLat               ! exchange factor for latent heat (W m-2)
 real(dp)                      :: scalarSenHeat             ! sensible heat flux at the surface (W m-2)
 real(dp)                      :: scalarLatHeat             ! latent heat flux at the surface (W m-2)
 real(dp)                      :: totalSurfaceFlux          ! total surface flux (W m-2)
 real(dp)                      :: dTotalSurfaceFlux_dTemp   ! derivative in total surface flux w.r.t. temperature (W m-2 K-1)
 ! local variables for the energy flux at layer interfaces
 real(dp),dimension(0:nLayers) :: iLayerNrgFlux             ! energy flux at the layer interfaces (W m-2)
 real(dp),dimension(0:nLayers) :: dFlux_dTempAbove          ! derivatives in the flux w.r.t. temperature in the layer above (J m-2 s-1 K-1)
 real(dp),dimension(0:nLayers) :: dFlux_dTempBelow          ! derivatives in the flux w.r.t. temperature in the layer below (J m-2 s-1 K-1)
 ! local variables for the residual vector
 real(dp)                      :: nrg0,nrg1                 ! energy content at the start of the time step / current iteration (J m-3)
 real(dp)                      :: flx0,flx1                 ! fluxes at the start of the time step / current iteration (J m-3)
 real(dp)                      :: phse                      ! phase change term (J m-3)
 ! -------------------------------------------------------------------------------------------------------
 ! initialize error control
 err=0; message='nrg_residl/'

 ! ***** compute fluxes at layer interfaces and their derivatives (J m-2 s-1)
 call iLayer_nrg(&
                 ! (model control variables)
                 fDerivMeth,             & ! intent(in): method used to compute derivatives (numerical or analytical)
                 ! (input)
                 mLayerDepth,            & ! intent(in): depth of each layer (m)
                 mLayerHeight,           & ! intent(in): height of layer mid-points (m)
                 iLayerThermalC,         & ! intent(in): thermal conductivity at layer interfaces (W m-1)
                 mLayerTempTrial,        & ! intent(in): trial temperature at the current iteration (K)
                 totalSurfaceFlux,       & ! intent(in): total flux at the surface (W m-2)
                 dTotalSurfaceFlux_dTemp,& ! intent(in): derivative in total surface flux w.r.t. temperature (W m-2 K-1)
                 lowerBoundTemp,         & ! intent(in): temperature of the lower boundary (K)
                 ! (output)
                 iLayerNrgFlux,          & ! intent(out): energy flux at the layer interfaces (W m-2)
                 dFlux_dTempAbove,       & ! intent(out): derivatives in the flux w.r.t. temperature in the layer above (W m-2 K-1)
                 dFlux_dTempBelow,       & ! intent(out): derivatives in the flux w.r.t. temperature in the layer below (W m-2 K-1)
                 err,cmessage)             ! intent(out): error control
 if(err/=0)then; message=trim(message)//trim(cmessage); return; endif

 ! ***** compute the residual vector (J m-3)
 do iLayer=1,nLayers
  ! (compute individual terms)
  nrg0 = mLayerVolHtCapBulk(iLayer)*mLayerTemp(iLayer)       ! energy content at the start of the time step (J m-3)
  nrg1 = mLayerVolHtCapBulk(iLayer)*mLayerTempTrial(iLayer)  ! energy content at the current iteration (J m-3)
  flx0 = -(iLayerInitNrgFlux(iLayer) - iLayerInitNrgFlux(iLayer-1))*(dt/mLayerDepth(iLayer))  ! flux at the start of the time step (J m-3)
  flx1 = -(iLayerNrgFlux(iLayer) - iLayerNrgFlux(iLayer-1))*(dt/mLayerDepth(iLayer))          ! flux at the current iteration (J m-3)
  phse = LH_fus*iden_ice*(mLayerVolFracIceTrial(iLayer) - mLayerVolFracIce(iLayer))   ! phase change term (J m-3)
  ! (compute residuals)
  rvec(iLayer) = nrg1 - (nrg0 + flx0*wimplicit + flx1*(1._dp - wimplicit) + phse)
  ! (print progress)
  !if(iLayer < 5) write(*,'(a,1x,i4,1x,f9.3,1x,10(e20.10,1x))') 'residuals = ', iLayer, mLayerTempTrial(iLayer), rvec(iLayer), nrg0, nrg1, (nrg1 - nrg0), flx0, flx1, phse
 end do

 end subroutine nrg_residl


 ! ************************************************************************************************
 ! private function: compute derivative in specific humidity w.r.t. temperature (kg kg-1 K-1)
 ! ************************************************************************************************
 function dsphum_dTk(r_hum, apres, Tk)
 ! compute derivative in specific humidity w.r.t. temperature (kg kg-1 K-1)
 ! (based on Teten's formula))
 USE multiconst,only:TFreeze, &            ! temperature at freezing              (K)
                     satvpfrz,&            ! sat vapour pressure at 273.16K       (Pa)
                     w_ratio               ! molecular ratio water to dry air     (-)
 implicit none
 ! dummies
 real(dp),intent(in)         :: r_hum       ! relative humidity (fraction)
 real(dp),intent(in)         :: apres       ! atmospheric pressure (Pa)
 real(dp),intent(in)         :: Tk          ! temperature (K)
 real(dp)                    :: dsphum_dTk  ! derivative in specific humidity w.r.t. temperature (kg kg-1 K-1)
 ! locals
 real(dp)                    :: Tc          ! temperature (oC)
 real(dp)                    :: pvp         ! partial vapour pressure (Pa)
 real(dp)                    :: pvp_p       ! derivative in partial vapor pressure w.r.t. temperature (Pa K-1)
 real(dp),parameter          :: a= 17.27_dp ! 1st parameter in Teten's formula for partial vapor pressure (-)
 real(dp),parameter          :: b=237.30_dp ! 2nd parameter in Teten's formula for partial vapor pressure (K))
 ! convert temperature to deg C
 Tc  = Tk - Tfreeze
 ! compute the partial vapour pressure (Pa)
 pvp = r_hum * satVpFrz * exp( a*Tc/(b + Tc) )
 ! compute the derivative in partial vapor pressure w.r.t. temperature (Pa/K)
 pvp_p = pvp * (a/(b + Tc) - (a*Tc)/(b + Tc)**2._dp)
 ! compute the derivative in specific humidity w.r.t. temperature (kg kg-1 K-1)
 dsphum_dTk = w_ratio*pvp_p/(apres - (1._dp - w_ratio)*pvp) + &
              w_ratio*(1._dp - w_ratio)*pvp*pvp_p/(apres - (1._dp - w_ratio)*pvp)**2._dp
 end function dsphum_dTk



 ! ************************************************************************************************
 ! private subroutine: line search
 ! ************************************************************************************************
 SUBROUTINE lnsrch(&
                   ! (model control variables)
                   dt,                      & ! intent(in): time step (seconds)
                   fDerivMeth,              & ! intent(in): method used to compute derivatives (numerical or analytical)
                   ixGroundwater,           & ! intent(in): choice of groundwater representation
                   ! (model forcing variables)
                   airtemp,                 & ! intent(in): air temperature (K)
                   spechum,                 & ! intent(in): specific humidity (g g-1)
                   windspd,                 & ! intent(in): wind speed (m s-1)
                   airpres,                 & ! intent(in): air pressure (Pa)
                   sw_down,                 & ! intent(in): downwelling shortwave radiation (W m-2)   
                   lw_down,                 & ! intent(in): downwelling long wave radiation (W m-2)   
                   lowerBoundTemp,          & ! intent(in): temperature of the lower boundary (K)
                   ! (model parameters)
                   mHeight,                 & ! intent(in): measurement height (m)
                   wimplicit,               & ! intent(in): weight assigned to start-of-step values (-)
                   ! (coordinate variables)
                   mLayerDepth,             & ! intent(in): depth of each layer (m)
                   mLayerHeight,            & ! intent(in): height of layer mid-points (m)
                   iLayerHeight,            & ! intent(in): height of layer interfaces (m)
                   ! (diagnostic variables)
                   scalarTranspireLim,      & ! intent(in): aggregate soil moist & veg limit on transpiration, weighted by root density (-)
                   iLayerThermalC,          & ! intent(in): thermal conductivity at layer interfaces (W m-1)
                   mLayerVolHtCapBulk,      & ! intent(in): volumetric heat capacity in each layer (J m-3)
                   iLayerInitNrgFlux,       & ! intent(in): energy flux at layer interfaces at the start of the step (W m-2)
                   ! (state variables at start of step)
                   scalarAlbedo,            & ! intent(in): surface albedo (-)
                   mLayerTemp,              & ! intent(in): temperature in all layers (K)
                   mLayerVolFracIce,        & ! intent(in): volumetric fraction of ice in all layers (-)
                   ! (trial state variables)
                   xold,                    & ! intent(in): trial temperature vector (K)
                   mLayerMatricHeadIter,    & ! intent(in): matric head at the current iteration (m)
                   mLayerVolFracLiqIter,    & ! intent(in): volumetric fraction of liquid water at the current iteration (-)
                   mLayerVolFracIceIter,    & ! intent(in): volumetric fraction of ice at the current iteration (-)
                   ! (functions and gradients)
                   stpmax,                  & ! intent(in): maximum step size (K)
                   fold,                    & ! intent(in): function value for trial temperature vector (J m-3 J m-3)
                   g,                       & ! intent(in): gradient of the function vector (J m-3 J m-3 K-1)
                   p,                       & ! intent(inout): iteration increment (K)
                   ! output
                   x,                       & ! intent(out): new temperature vector (K)
                   rvec,                    & ! intent(out): new residual vector (J m-3)
                   f,                       & ! intent(out): new function value (J m-3 J m-3)
                   mLayerMatricHeadNew,     & ! intent(out): new matric head (m)
                   mLayerVolFracLiqNew,     & ! intent(out): new volumetric fraction of liquid water (-)
                   mLayerVolFracIceNew,     & ! intent(out): new volumetric fraction of ice (-)
                   err,message)               ! intent(out): error control
 USE phseChange_module,only:phseChange       ! compute change in phase over the time step
 IMPLICIT NONE
 ! input (control)
 real(dp),intent(in)           :: dt                       ! intent(in): time step (seconds)
 integer(i4b),intent(in)       :: fDerivMeth               ! intent(in): method used to calculate derivatives
 integer(i4b),intent(in)       :: ixGroundwater            ! intent(in): choice of groundwater representation
 ! input (forcing)
 real(dp),intent(in)           :: airtemp                  ! intent(in): air temperature (K)
 real(dp),intent(in)           :: spechum                  ! intent(in): specific humidity (g g-1)
 real(dp),intent(in)           :: windspd                  ! intent(in): wind speed (m s-1)
 real(dp),intent(in)           :: airpres                  ! intent(in): air pressure (Pa)
 real(dp),intent(in)           :: sw_down                  ! intent(in): downwelling shortwave radiation (W m-2)   
 real(dp),intent(in)           :: lw_down                  ! intent(in): downwelling long wave radiation (W m-2)   
 real(dp),intent(in)           :: lowerBoundTemp           ! intent(in): temperature of the lower boundary (K)
 ! input (parameters)
 real(dp),intent(in)           :: mHeight                  ! intent(in): measurement height (m)
 real(dp),intent(in)           :: wimplicit                ! intent(in): weight assigned to start-of-step values (-)
 ! input (coordinate variables)
 real(dp),intent(in)           :: mLayerDepth(:)           ! intent(in): depth of each layer (m)
 real(dp),intent(in)           :: mLayerHeight(:)          ! intent(in): height of layer mid-points (m)
 real(dp),intent(in)           :: iLayerHeight(0:)         ! intent(in): height of layer interfaces (m)
 ! input (diagnostic variables)
 real(dp),intent(in)           :: scalarTranspireLim       ! intent(in): resistance to evaporation at the surface (-)
 real(dp),intent(in)           :: iLayerThermalC(0:)       ! intent(in): thermal conductivity at layer interfaces (W m-1)
 real(dp),intent(in)           :: mLayerVolHtCapBulk(:)    ! intent(in): volumetric heat capacity in each layer (J m-3)
 real(dp),intent(in)           :: iLayerInitNrgFlux(0:)    ! intent(in): energy flux at layer interfaces at the start of the step (W m-2)
 ! input (state variables at the start of the step)
 real(dp),intent(in)           :: scalarAlbedo             ! intent(in): surface albedo (-)
 real(dp),intent(in)           :: mLayerTemp(:)            ! intent(in): temperature in all layers (K)
 real(dp),intent(in)           :: mLayerVolFracIce(:)      ! intent(in): volumetric fraction of ice in all layers (-)
 ! input (trial state variables)
 real(dp),intent(in)           :: xold(:)                  ! intent(in): trial temperature vector (K)      
 real(dp),intent(in)           :: mLayerMatricHeadIter(:)  ! intent(in): before phase change: matric head (m)
 real(dp),intent(in)           :: mLayerVolFracLiqIter(:)  ! intent(in): before phase change: volumetric fraction of liquid water (-)
 real(dp),intent(in)           :: mLayerVolFracIceIter(:)  ! intent(in): before phase change: volumetric fraction of ice (-)
 ! input: (functions and gradients)
 real(dp),intent(in)           :: stpmax                   ! intent(in): maximum step size (K)
 real(dp),intent(in)           :: fold                     ! intent(in): function value for trial temperature vector (J m-3 J m-3)
 real(dp),intent(in)           :: g(:)                     ! intent(in): gradient of the function vector (J m-3 J m-3 K-1)
 real(dp),intent(inout)        :: p(:)                     ! intent(inout): iteration increment (K)
 ! output
 real(dp),intent(out)          :: x(:)                     ! intent(out): new temperature vector (K)
 real(dp),intent(out)          :: rvec(:)                  ! intent(out): new residual vector (J m-3)                     
 real(dp),intent(out)          :: f                        ! intent(out): new function value (J m-3 J m-3)
 real(dp),intent(out)          :: mLayerMatricHeadNew(:)   ! intent(out): after phase change: matric head (m)
 real(dp),intent(out)          :: mLayerVolFracLiqNew(:)   ! intent(out): after phase change: volumetric fraction of liquid water (-)
 real(dp),intent(out)          :: mLayerVolFracIceNew(:)   ! intent(out): after phase change: volumetric fraction of ice (-)
 integer(i4b),intent(out)      :: err                      ! intent(out): error code
 character(*),intent(out)      :: message                  ! intent(out): error message
 ! local variables
 character(LEN=256)            :: cmessage                 ! error message of downwind routine
 REAL(DP), PARAMETER :: ALF=1.0e-4_dp,TOLX=epsilon(x)
 INTEGER(I4B) :: ndum
 REAL(DP) :: a,alam,alam2,alamin,b,disc,f2,fold2,pabs,rhs1,rhs2,slope,&
     tmplam
 ! initialize error control
 err=0; message="lnsrch/"
 ! check arguments
 if ( all((/size(g),size(p),size(x)/) == size(xold)) ) then
  ndum=size(xold)
 else
  err=20; message=trim(message)//"sizeMismatch"; return
 endif
 ! start procedure
 pabs=sqrt(dot_product(p,p))
 if (pabs > stpmax) p(:)=p(:)*stpmax/pabs
 slope=dot_product(g,p)
 alamin=TOLX/maxval(abs(p(:))/max(abs(xold(:)),1.0_dp))
 alam=1.0_dp
 do
  ! ***** update the temperature vector (K)
  x(:)=xold(:)+alam*p(:)
  ! ***** compute phase change
  call phsechange(x,                   & ! intent(in): new temperature vector (K)
                  mLayerMatricHeadIter,& ! intent(in): matric head at the current iteration (m)
                  mLayerVolFracLiqIter,& ! intent(in): volumetric fraction of liquid water at the current iteration (-)
                  mLayerVolFracIceIter,& ! intent(in): volumetric fraction of ice at the current iteration (-)
                  mLayerMatricHeadNew, & ! intent(out): new matric head (m)
                  mLayerVolFracLiqNew, & ! intent(out): new volumetric fraction of liquid water (-)
                  mLayerVolFracIceNew, & ! intent(out): new volumetric fraction of ice (-)
                  err,cmessage)          ! intent(out): error control
  if(err/=0)then; message=trim(message)//trim(cmessage); return; endif
  ! ***** compute residual vector
  call nrg_residl(&
                  ! (model control variables)
                  dt,                      & ! intent(in): time step (seconds)
                  fDerivMeth,              & ! intent(in): method used to compute derivatives (numerical or analytical)
                  ixGroundwater,           & ! intent(in): choice of groundwater representation
                  ! (model forcing variables)
                  airtemp,                 & ! intent(in): air temperature (K)
                  spechum,                 & ! intent(in): specific humidity (g g-1)
                  windspd,                 & ! intent(in): wind speed (m s-1)
                  airpres,                 & ! intent(in): air pressure (Pa)
                  sw_down,                 & ! intent(in): downwelling shortwave radiation (W m-2)   
                  lw_down,                 & ! intent(in): downwelling long wave radiation (W m-2)   
                  lowerBoundTemp,          & ! intent(in): temperature of the lower boundary (K)
                  ! (model parameters)
                  mHeight,                 & ! intent(in): measurement height (m)
                  wimplicit,               & ! intent(in): weight assigned to start-of-step values (-)
                  ! (coordinate variables)
                  mLayerDepth,             & ! intent(in): depth of each layer (m)
                  mLayerHeight,            & ! intent(in): height of layer mid-points (m)
                  iLayerHeight,            & ! intent(in): height of layer interfaces (m)
                  ! (diagnostic variables)
                  scalarTranspireLim,      & ! intent(in): aggregate soil moist & veg limit on transpiration, weighted by root density (-)
                  iLayerThermalC,          & ! intent(in): thermal conductivity at layer interfaces (W m-1)
                  mLayerVolHtCapBulk,      & ! intent(in): volumetric heat capacity in each layer (J m-3)
                  iLayerInitNrgFlux,       & ! intent(in): energy flux at layer interfaces at the start of the step (W m-2)
                  ! (state variables at start of step))
                  scalarAlbedo,            & ! intent(in): surface albedo (-)
                  mLayerTemp,              & ! intent(in): temperature in all layers (K)
                  mLayerVolFracIce,        & ! intent(in): volumetric fraction of ice in all layers (-)
                  ! (trial state variables)
                  x,                       & ! intent(in): trial temperature in all layers at the current iteration (K)
                  mLayerVolFracIceNew,     & ! intent(in): trial volumetric fraction of ice in all layers at the current iteration (-)
                  mLayerMatricHeadNew,     & ! intent(in): trial matric head in all layers at the current iteration (m)
                  ! (output)
                  rvec,                    & ! intent(out): residual vector (J m-3)
                  err,message)               ! intent(out): error control
  if(err/=0)then; message=trim(message)//trim(cmessage); return; endif
  ! compute the function evaluation
  f=0.5_dp*dot_product(rvec,rvec)
  ! additional exit criteria
  if(f<0.5_dp)return
  ! check if backtracked all the way to the original value
  if (alam < alamin) then
   x(:)=xold(:)
   err=-10; message=trim(message)//'warning: check convergence'
   RETURN
  ! check if improved the solution sufficiently
  else if (f <= fold+ALF*alam*slope) then
   RETURN
  ! build another trial vector
  else
   if (alam == 1.0_dp) then
    tmplam=-slope/(2.0_dp*(f-fold-slope))
   else
    rhs1=f-fold-alam*slope
    rhs2=f2-fold2-alam2*slope
    a=(rhs1/alam**2-rhs2/alam2**2)/(alam-alam2)
    b=(-alam2*rhs1/alam**2+alam*rhs2/alam2**2)/&
        (alam-alam2)
    if (a == 0.0_dp) then
     tmplam=-slope/(2.0_dp*b)
    else
     disc=b*b-3.0_dp*a*slope
     if (disc < 0.0_dp)then; err=-10; message=trim(message)//'warning: roundoff problem in lnsrch'; return; endif
     tmplam=(-b+sqrt(disc))/(3.0_dp*a)
    end if
    if (tmplam > 0.5_dp*alam) tmplam=0.5_dp*alam
   end if
  end if
  alam2=alam
  f2=f
  fold2=fold
  alam=max(tmplam,0.1_dp*alam)
 end do
 END SUBROUTINE lnsrch



end module heatTransf_module
