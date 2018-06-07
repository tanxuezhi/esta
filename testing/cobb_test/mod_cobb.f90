module mod_cobb

implicit none

contains

subroutine cobb(omega_m,T_m,rh_m,z_i,pres_m,ratio)

  implicit none

  real, intent(in) :: omega_m(:)
  real, intent(in) :: T_m(:)
  real, intent(in) :: rh_m(:)
  real, intent(in) :: z_i(:)
  real, intent(in) :: pres_m(:)
  real, intent(inout) :: ratio

  integer,parameter :: nlev = 3
  integer,parameter :: nlevp1 = 4
  
  ! local variables
  real,parameter,dimension(34) :: snowRatio_cobb = (/10.,10.,10.,10.,10.,10.,10.,10.,9.58,10.36,&
    13.07,19.11,28.39,38.80,46.98,50.,45.73,36.25,24.90,14.95,8.96,6.15,5.73,&
    5.99,6.35,6.35,6.15,5.83,5.16,4.53,3.70,2.81,0.0,0.0 /)
  real,parameter,dimension(34) :: layerTemp_cobb = (/-100.,-29.5,-28.5,-27.5,-26.5,-25.5,-24.5,&
    -23.5,-22.5,-21.5,-20.5,-19.5,-18.5,-17.5,-16.5,-15.5,-14.5,-13.5,-12.5,-11.5,&
    -10.5,-9.5,-8.5,-7.5,-6.5,-5.5,-4.5,-3.5,-2.5,-1.5,-0.5,0.5,25.,50. /)

  real, dimension(34) :: layerTempK, layerTemp
  real, dimension(34) :: snowRatio
  real :: delZ(nlev)
  real :: snowRatProfile(nlev)
  real :: weights(nlev)
  real :: snowRatWeights(nlev)
  real :: omega_sub(nlev),rh_sub(nlev)

  real, parameter :: CtoK = 273.15
  real, parameter :: rh_crit = 90.
  real, parameter :: p_top = 25000. ! Pa

  integer :: k
  integer :: ix

  real :: omega_max
  real :: weights_sum

  omega_sub = omega_m
  rh_sub = rh_m

  ! Filter out levels above XXX mb
  WHERE(pres_m.ge.p_top)
    omega_sub = omega_sub
    rh_sub = rh_sub
  ELSEWHERE
    omega_sub = 0
    rh_sub = 0 
  END WHERE

  !print *,pres_m
  !print *,T_m
  !print *,z_i

  layerTemp = layerTemp_cobb + CtoK
  snowRatio = snowRatio_cobb

  do k = 1,nlev
    ix = minloc(abs(T_m(k)-layerTemp),DIM=1)
    snowRatProfile(k) = snowRatio(ix)
  end do

  delZ=z_i(1:nlevp1-1)-z_i(2:nlevp1)

  WHERE(rh_sub.ge.rh_crit)
    omega_sub = omega_sub
  ELSEWHERE
    omega_sub = 0 
  END WHERE



  WHERE(omega_sub.le.0.0)
    omega_sub = 0
  ELSEWHERE
    omega_sub = omega_sub 
  END WHERE

  omega_max = MAXVAL(omega_sub)

  IF (omega_max .gt. 0.0) THEN
    weights = omega_sub(:)*(omega_sub(:)/omega_max)**2*delZ(:)
    weights_sum = sum(weights)
    snowRatWeights = snowRatProfile*weights
    ratio = sum(snowRatWeights)/weights_sum
  ELSE
    ratio = 10.0
  END IF

  ! Check for NaN before sending back
  if (isnan(ratio)) ratio = 10.0

end subroutine cobb


subroutine bourgouin(pres_m,pres_i,T_m,ptype)

  implicit none

  real, intent(in) :: pres_m(:)
  real, intent(in) :: pres_i(:)
  real, intent(in) :: T_m(:)
  real, intent(inout) :: ptype

  integer,parameter :: nlev = 30
  integer,parameter :: nlevp1 = 31

  ! Declare local variables
  real :: pres_i_top(nlev)
  real :: pres_i_bot(nlev)
  real :: area(nlev)
  integer :: area_sign(nlev)
  integer :: signchange
  integer :: counter
  REAL, DIMENSION(:), ALLOCATABLE :: area_arr,dumareaPA,dumareaNA
  real :: PA_a, PA_sfc, NA, PA

  ! Loop indices
  integer :: i,j,k
  integer :: AllocateStatus,DeAllocateStatus

  ! Declare local constants
  REAL, PARAMETER :: eps = 10E-10
  REAL, PARAMETER :: Rd = 287.0
  REAL, PARAMETER :: cp = 1004.0
 
  pres_i_top = pres_i(1:nlev)
  pres_i_bot = pres_i(2:nlev+1)

  !print *,pres_i_top


  area = -cp*(T_m-273.15)*log(pres_i_top/pres_i_bot)
!  area = where(abs(area).le.eps,eps,area)

  WHERE(abs(area)<eps)
    area = eps
  ELSEWHERE
    area = area 
  END WHERE

  !print *,area

  area_sign = area/abs(area)

  ! Find number of sign changes
  signchange = 0
  DO k = 1,SIZE(area_sign)-1
    IF (area_sign(k) - area_sign(k+1) .NE. 0) THEN
      signchange = signchange+1
    END IF
  END DO


  IF (signchange .eq. 0) THEN
    ! SNOW
    ptype = 0
  ELSE
    !== We need to calculate PA/NA
    ALLOCATE( area_arr(signchange+1), STAT=AllocateStatus)
    IF (AllocateStatus /= 0) STOP "*** Not enough memory ***"
  
    area_arr=0
    counter=1
    DO k = 1,SIZE(area_sign)-1
      area_arr(counter) = area_arr(counter)+area(k)
      IF (area_sign(k) - area_sign(k+1) .NE. 0) THEN
        counter = counter+1
      END IF
    END DO
    ! Need to add last bit?
    area_arr(counter) = area_arr(counter)+area(SIZE(area_sign))

    IF (signchange .eq. 1) THEN
      PA = area_arr(2)
      IF (PA.lt.5.6) THEN
        ! === SNOW
        ptype = 0
      ELSE IF (PA.gt.13.2) THEN
        ! === RAIN
        ptype = 2
      ELSE
        ! === MIX
        ptype = 1
      END IF
    ELSE IF (signchange .eq. 2) THEN
      ! area_arr(0) wasted stuff above first cross
      ! area_arr(1) PA
      ! area_arr(2) NA
      PA = area_arr(2)
      NA = -area_arr(3)
      !print("PA: "+PA+"    NA: "+NA)
      IF (NA .gt. 66+0.66*PA) THEN
        ! ==== ICE
        ptype = 3
      ELSE IF (NA .lt. 46+0.66*PA) THEN
        ! ==== FZRA
        ptype = 4
      ELSE
        ! ==== MIX OF FZRA/ICE
        ptype = 1
      END IF
    ELSE IF (signchange .eq. 3) THEN
      ! area_arr(0) wasted stuff above first cross
      ! area_arr(1) PA_a
      ! area_arr(2) NA
      ! area_arr(3) PA_sfc
      PA_a = area_arr(2)
      NA = -area_arr(3)
      PA_sfc = area_arr(4)
      if (PA_a .gt. 2) then
      ! we use Eqn 4
        if (NA .gt. 66+0.66*PA_sfc) then
          ! ==== ICE
          ptype = 3
        else if (NA .lt. 46+0.66*PA_sfc) then
          ! ==== RAIN
          ptype = 2
        else
          ! ==== MIX OF ICE/RAIN
          ptype = 1
        end if
      else
        if (PA_sfc.lt.5.6) then
          ! === ICE
          ptype = 3
        else if (PA_sfc.gt.13.2) then
          ! === RAIN
          ptype = 2
        else
          ! === MIX
          ptype = 1
        end if
      end if
    else
      if (mod(signchange,2) .eq. 0) then
        area_arr(1)=0
      
        ! Need to allocate dummy arrays
        ALLOCATE( dumareaPA(signchange+1), STAT=AllocateStatus)
        IF (AllocateStatus /= 0) STOP "*** Not enough memory ***"
        ALLOCATE( dumareaNA(signchange+1), STAT=AllocateStatus)
        IF (AllocateStatus /= 0) STOP "*** Not enough memory ***"

        dumareaPA = area_arr
        dumareaNA = area_arr
        WHERE(area_arr .LT. 0) dumareaPA = 0
        WHERE(area_arr .GT. 0) dumareaNA = 0
        PA = sum(dumareaPA)
        NA = -sum(dumareaNA)

          if (NA .gt. 66+0.66*PA) then
            !; ==== ICE
            ptype = 3
            !print("ICE")
          else if (NA .lt. 46+0.66*PA) then
            !; ==== FZRA
            ptype = 4
            !print("FRZRA")
          else
            !; ==== MIX OF FZRA/ICE
            ptype = 1
            !print("MIX")
          end if
      else 
        area_arr(1)=0
        PA_sfc = area_arr(SIZE(area_arr))
        area_arr(SIZE(area_arr)) = 0

        ! Need to allocate dummy arrays
        ALLOCATE( dumareaPA(signchange+1), STAT=AllocateStatus)
        IF (AllocateStatus /= 0) STOP "*** Not enough memory ***"
        ALLOCATE( dumareaNA(signchange+1), STAT=AllocateStatus)
        IF (AllocateStatus /= 0) STOP "*** Not enough memory ***"

        dumareaPA = area_arr
        dumareaNA = area_arr
        WHERE(area_arr .LT. 0) dumareaPA = 0
        WHERE(area_arr .GT. 0) dumareaNA = 0
        PA_a = sum(dumareaPA)
        NA = -sum(dumareaNA)

        !;print("PA_a: "+PA_a+"    NA: "+NA+"    PA_sfc: "+PA_sfc)
        !;print(area)
        if (PA_a .gt. 2) then
        !; we use Eqn 4
          if (NA .gt. 66+0.66*PA_sfc) then
            !; ==== ICE
            ptype = 3
          else if (NA .lt. 46+0.66*PA_sfc) then
            !; ==== RAIN
            ptype = 2
          else
            !; ==== MIX OF ICE/RAIN
            ptype = 1
          end if
        else
          if (PA_sfc.lt.5.6) then
            !; === ICE
            ptype = 3
          else if (PA_sfc.gt.13.2) then
            !; === RAIN
            ptype = 2
          else
            !; === MIX
            ptype = 1
          end if
        end if
        DEALLOCATE (dumareaPA, STAT = DeAllocateStatus)
        IF (DeAllocateStatus /= 0) STOP "*** Deallocate failed ***"
        DEALLOCATE (dumareaNA, STAT = DeAllocateStatus)
        IF (DeAllocateStatus /= 0) STOP "*** Deallocate failed ***"
      end if  
    end if

  DEALLOCATE (area_arr, STAT = DeAllocateStatus)
  IF (DeAllocateStatus /= 0) STOP "*** Deallocate failed ***"
  end if

end subroutine bourgouin

!
!
!$$$  Subprogram documentation block
!
! Subprogram: calwxt_bourg    Calculate precipitation type (Bourgouin)
!   Prgmmr: Baldwin      Org: np22        Date: 1999-07-06
!
! Abstract: This routine computes precipitation type
!    using a decision tree approach that uses the so-called
!    "energy method" of Bourgouin of AES (Canada) 1992
!
! Program history log:
!   1999-07-06  M Baldwin
!   1999-09-20  M Baldwin  make more consistent with bourgouin (1992)
!   2005-08-24  G Manikin  added to wrf post
!   2007-06-19  M Iredell  mersenne twister, best practices
!   2008-03-03  G Manikin  added checks to prevent stratospheric warming
!                           episodes from being seen as "warm" layers
!                           impacting precip type
!
! Usage:    call calwxt_bourg(im,jm,jsta_2l,jend_2u,jsta,jend,lm,lp1,   &
!    &                        iseed,g,pthresh,                          &
!    &                        t,q,pmid,pint,lmh,prec,zint,ptype)
!   Input argument list:
!     im       integer i dimension
!     jm       integer j dimension
!     jsta_2l  integer j dimension start point (including haloes)
!     jend_2u  integer j dimension end point (including haloes)
!     jsta     integer j dimension start point (excluding haloes)
!     jend     integer j dimension end point (excluding haloes)
!     lm       integer k dimension
!     lp1      integer k dimension plus 1
!     iseed    integer random number seed
!     g        real gravity (m/s**2)
!     pthresh  real precipitation threshold (m)
!     t        real(im,jsta_2l:jend_2u,lm) mid layer temp (K)
!     q        real(im,jsta_2l:jend_2u,lm) specific humidity (kg/kg)
!     pmid     real(im,jsta_2l:jend_2u,lm) mid layer pressure (Pa)
!     pint     real(im,jsta_2l:jend_2u,lp1) interface pressure (Pa)
!     lmh      real(im,jsta_2l:jend_2u) max number of layers
!     prec     real(im,jsta_2l:jend_2u) precipitation (m)
!     zint     real(im,jsta_2l:jend_2u,lp1) interface height (m)
!   Output argument list:
!     ptype    real(im,jm) instantaneous weather type ()
!              acts like a 4 bit binary
!                1111 = rain/freezing rain/ice pellets/snow
!                where the one's digit is for snow
!                      the two's digit is for ice pellets
!                      the four's digit is for freezing rain
!                  and the eight's digit is for rain
!              in other words...
!                ptype=1 snow
!                ptype=2 ice pellets/mix with ice pellets
!                ptype=4 freezing rain/mix with freezing rain
!                ptype=8 rain
!
! Modules used:
!   mersenne_twister pseudo-random number generator
!
! Subprograms called:
!   random_number    pseudo-random number generator
!
! Attributes:
!   Language: Fortran 90
!
! Remarks: vertical order of arrays must be layer   1 = top
!                                       and layer lmh = bottom
!
!$$$
      subroutine calwxt_bourg(lm,lp1,t,pmid,pint,zint,ptype)

      implicit none
!
!    input:
      integer,intent(in):: lm,lp1
      real,intent(in):: t(lm)
      real,intent(in):: pmid(lm)
      real,intent(in):: pint(lp1)
      real,intent(in):: zint(lp1)
!
!    output:
      real,intent(out):: ptype
!
      integer :: ifrzl,iwrml,l,lhiwrm,lmhk
      real :: pintk1,areane,tlmhk,areape,pintk2,surfw,area1,dzkl,psfck
      real :: r1,r2
      real,parameter :: g=9.81
!
!     initialize weather type array to zero (ie, off).
!     we do this since we want ptype to represent the
!     instantaneous weather type on return.

      r1 = 0.4
      r2 = 0.6

      ptype = 0

!
!      call random_number(rn,iseed)
!
!!$omp  parallel do
!!$omp& private(a,lmhk,tlmhk,iwrml,psfck,lhiwrm,pintk1,pintk2,area1,
!!$omp&         areape,dzkl,surfw,r1,r2)

      psfck=pint(lm+1)

!     find the depth of the warm layer based at the surface
!     this will be the cut off point between computing
!     the surface based warm air and the warm air aloft
!
!
!     lowest layer t
!
      tlmhk = t(lm)
      iwrml = lm + 1
      if (tlmhk.ge.273.15) then
        do l = lm, 2, -1
         if (t(l).ge.273.15.and.t(l-1).lt.273.15.and.           &
     &            iwrml.eq.lm+1) iwrml = l
          end do
      end if
!
!     now find the highest above freezing level
!
      lhiwrm = lm + 1
      do l = lm, 1, -1
! gsm  added 250 mb check to prevent stratospheric warming situations
!       from counting as warm layers aloft      
          if (t(l).ge.273.15 .and. pmid(l).gt.25000.) lhiwrm = l
      end do

!     energy variables
!     surfw is the positive energy between the ground
!     and the first sub-freezing layer above ground
!     areane is the negative energy between the ground
!     and the highest layer above ground
!     that is above freezing
!     areape is the positive energy "aloft"
!     which is the warm energy not based at the ground
!     (the total warm energy = surfw + areape)
!
!     pintk1 is the pressure at the bottom of the layer
!     pintk2 is the pressure at the top of the layer
!     dzkl is the thickness of the layer
!     ifrzl is a flag that tells us if we have hit
!     a below freezing layer
!
      pintk1 = psfck
      ifrzl = 0
      areane = 0.0
      areape = 0.0
      surfw = 0.0                                         

      do l = lm, 1, -1
          if (ifrzl.eq.0.and.t(l).le.273.15) ifrzl = 1
          pintk2=pint(l)
          dzkl=zint(l)-zint(l+1)
          area1 = log(t(l)/273.15) * g * dzkl
          if (t(l).ge.273.15.and. pmid(l).gt.25000.) then
              if (l.lt.iwrml) areape = areape + area1
              if (l.ge.iwrml) surfw = surfw + area1
          else
              if (l.gt.lhiwrm) areane = areane + abs(area1)
          end if
          pintk1 = pintk2
      end do
      
!
!     decision tree time
!
      if (areape.lt.2.0) then
!         very little or no positive energy aloft, check for
!         positive energy just above the surface to determine rain vs. snow
          if (surfw.lt.5.6) then
!             not enough positive energy just above the surface
!             snow = 0
              ptype = 0
          else if (surfw.gt.13.2) then
!             enough positive energy just above the surface
!             rain = 2
              ptype = 2
          else
!             transition zone, assume equally likely rain/snow
!             picking a random number, if <=0.5 snow
              !r1 = rn(1)
              if (r1.le.0.5) then
!                 snow = 0
                  ptype = 0
              else
!                 rain = 2
                  ptype = 2
              end if
          end if
!
      else
!         some positive energy aloft, check for enough negative energy
!         to freeze and make ice pellets to determine ip vs. zr
          if (areane.gt.66.0+0.66*areape) then
!             enough negative area to make ip,
!             now need to check if there is enough positive energy
!             just above the surface to melt ip to make rain
              if (surfw.lt.5.6) then
!                 not enough energy at the surface to melt ip
!                 ice pellets = 3
                  ptype = 3
              else if (surfw.gt.13.2) then
!                 enough energy at the surface to melt ip
!                 rain = 2
                  ptype = 2
              else
!                 transition zone, assume equally likely ip/rain
!                 picking a random number, if <=0.5 ip
                  !r1 = rn(1)
                  if (r1.le.0.5) then
!                     ice pellets = 3
                      ptype = 3
                  else
!                     rain = 2
                      ptype = 2
                  end if
              end if
          else if (areane.lt.46.0+0.66*areape) then
!             not enough negative energy to refreeze, check surface temp
!             to determine rain vs. zr
              if (tlmhk.lt.273.15) then
!                 freezing rain = 4
                  ptype = 4
              else
!                 rain = 2
                  ptype = 2
              end if
          else
!             transition zone, assume equally likely ip/zr
!             picking a random number, if <=0.5 ip
              !r1 = rn(1)
              if (r1.le.0.5) then
!                 still need to check positive energy
!                 just above the surface to melt ip vs. rain
                  if (surfw.lt.5.6) then
!                     ice pellets = 3
                      ptype = 3
                  else if (surfw.gt.13.2) then
!                     rain = 2
                      ptype = 2
                  else
!                     transition zone, assume equally likely ip/rain
!                     picking a random number, if <=0.5 ip
                      !r2 = rn(2)
                      if (r2.le.0.5) then
!                         ice pellets = 3
                          ptype = 3
                      else
!                         rain = 2
                          ptype = 2
                      end if
                  end if
              else
!                 not enough negative energy to refreeze, check surface temp
!                 to determine rain vs. zr
                  if (tlmhk.lt.273.15) then
!                     freezing rain = 4
                      ptype = 4
                  else
!                     rain = 2
                      ptype = 2
                  end if
              end if
          end if
      end if
!      end do
!      end do
      return
end subroutine calwxt_bourg

subroutine init_random_seed

      INTEGER :: i, n, clock
      INTEGER, DIMENSION(:), ALLOCATABLE :: seed

      CALL RANDOM_SEED(size = n)
      ALLOCATE(seed(n))

      CALL SYSTEM_CLOCK(COUNT=clock)

      seed = clock + 37 * (/ (i - 1, i = 1, n) /)
      print *,seed
      CALL RANDOM_SEED(PUT = seed)

      DEALLOCATE(seed)

end subroutine init_random_seed



end module mod_cobb

