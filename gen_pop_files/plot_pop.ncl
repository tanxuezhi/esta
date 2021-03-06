;========================================================
; This file reads in a traj file produced by the TC tracker
; and produces a lat-lon plot of trajectories color-coded by intensity
;========================================================
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_code.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_csm.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/contributed.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/shea_util.ncl"
load "/glade/u/home/zarzycki/ecsnow/shapefile_ncl/shapefile_mask_data.ncl"
;========================================================
begin

debug=False
outputMask=False
useExistingMask=True
maskFileName="NEmask.nc"
popFilePath="/glade/u/home/zarzycki/ecsnow/gen_pop_files/population.nc"
imgDir="./images"
RSIoutFile="./RSI.ecsnow30x4.csv"
stormFilePath="/glade/scratch/zarzycki/simple.nc"

if (isdefined("ensmember") .and. ensmember .ne. "XXX")
  stormFilePath="/glade/u/home/zarzycki/scratch/LES_snow/LESsimple."+ensmember+".nc"
  imgDir="/glade/u/home/zarzycki/scratch/LES_snow/images/"+ensmember+"/"
  RSIoutFile="/glade/u/home/zarzycki/scratch/LES_snow/RSI.LES."+ensmember+".csv"
else
  ensmember="XXX"
end if

if (.not. isdefined("stormID"))
  stormID=84
  print("WARNING: stormID not defined, defaulting to id: "+stormID)
end if

;=====================================================

f=addfile(stormFilePath,"r")
popFile=addfile(popFilePath,"r")
POP=popFile->POP({37:49},{-82:-66})
POP=POP/1000
AREA=popFile->AREA({37:49},{-82:-66})
SNOW=f->CUM_SNOWFALL(toint(stormID),{37:49},{-82+360.:-66+360.})
;lon=f->lon
;lat=f->lat
lon=-(360.-SNOW&lon)
SNOW&lon=lon

;newlat=fspan(min(lat),max(lat),toint((max(lat)-min(lat))*10.))
;newlon=fspan(min(lon),max(lon),toint((max(lon)-min(lon))*10.))
;newlat@units="degrees_north"
;newlon@units="degrees_east"

print("Interpolating snowfall to population grid...")
SNOWINT=linint2_Wrap(SNOW&lon,SNOW&lat,SNOW,False,POP&lon,POP&lat, 0)
print("... done interpolating")

print("Masking...")
if (useExistingMask) then
  maskFile=addfile(maskFileName,"r")
  MASK=maskFile->MASK
  SNOW_MASK=SNOWINT
  POP_MASK=POP
  AREA_MASK=AREA
  SNOW_MASK = where(MASK.gt.0.5,SNOWINT,SNOWINT@_FillValue)
  POP_MASK = where(MASK.gt.0.5,POP,POP@_FillValue)
  AREA_MASK = where(MASK.gt.0.5,AREA,AREA@_FillValue)
else
  shp_filename="/glade/u/home/zarzycki/ecsnow/shapefile_ncl/statesp010g.shp"
  opt = True 
  opt@minlat=37.
  opt@maxlat=49.
  opt@minlon=-82.
  opt@maxlon=-66.
  opt@shape_var = "NAME" 
  opt@shape_names = (/"Pennsylvania","New Jersey","Delaware","Maryland","Massachusetts","New York","Connecticut","Vermont","Maine","Rhode Island","New Hampshire"/)
  opt@DEBUG="True"
  SNOW_MASK = shapefile_mask_data(SNOWINT,shp_filename,opt)
  POP_MASK = shapefile_mask_data(POP,shp_filename,opt) 
  AREA_MASK = shapefile_mask_data(AREA,shp_filename,opt)
  if(outputMask) then
    MASK=AREA_MASK
    MASK=where(ismissing(AREA_MASK),0.0,1.0)
    system("/bin/rm -f "+maskFileName)   ; remove any pre-existing file
    ncdf = addfile(maskFileName ,"c")  ; open output netCDF file
    fAtt               = True            ; assign file attributes
    fAtt@Conventions   = "None"
    fAtt@creation_date = systemfunc ("date")
    fileattdef( ncdf, fAtt )
    ncdf->MASK  = MASK
  end if
end if
print("... done masking")

AREA_MASK = AREA_MASK*0.386102 ;convert to mi2

thresh=(/4,10,20,30/)
areaThresh=(/100885.0,52267.0,15975.0,4013.0/)
popThresh=(/19372985.0,10077690.0,3132697.0,873775.0/)
sumsArray = new(4,"float")
areaArray = sumsArray
popArray = sumsArray
;areaArray=(/152068.0,97897.0,56343.0,28830.0/)
;popArray=(/26559450.0,19090440.0,9803790.0,3448690.0/)


do i = 0,3
  POP_MASK = where(SNOW_MASK.ge.thresh(i),POP_MASK,POP_MASK@_FillValue)
  AREA_MASK = where(SNOW_MASK.ge.thresh(i),AREA_MASK,AREA_MASK@_FillValue)
  areaArray(i) = sum(AREA_MASK)
  popArray(i) = sum(POP_MASK)
  print("area: "+areaArray(i)+"   pop: "+popArray(i))
  sumsArray(i) = areaArray(i)/areaThresh(i) + popArray(i)/popThresh(i)
end do

RSIval=sum(sumsArray)

if (ismissing(RSIval)) then
  RSIval=0.0
end if

RSIcat=0
if (ismissing(RSIval) .or. RSIval .lt. 1) then
  RSIcat=0
else if (RSIval .ge. 1 .and. RSIval .lt. 3) then
  RSIcat=1
else if (RSIval .ge. 3 .and. RSIval .lt. 6) then
  RSIcat=2
else if (RSIval .ge. 6 .and. RSIval .lt. 10) then
  RSIcat=3
else if (RSIval .ge. 10 .and. RSIval .lt. 18) then
  RSIcat=4
else if (RSIval .ge. 18) then
  RSIcat=5
else
  print("error calculating RSI cat")
  exit
end if
end if
end if
end if
end if
end if

print(sum(sumsArray))

quote = inttochar(34)
system("echo "+quote +ensmember+","+stormID+","+RSIval+","+RSIcat    +quote+" >> "+RSIoutFile)


;1	1–3	Notable
;2	3–6	Significant
;3	6–10	Major
;4	10–18	Crippling
;5	18.0+	Extreme


;******************************************************
; create snowfall map
;******************************************************
wks = gsn_open_wks("pdf","pop_map")               ; open workstation
gsn_define_colormap(wks,"WhiteYellowOrangeRed")   ; choose colormap

res                     = True         ; plot modifications desired
res@gsnSpreadColors     = True         ; Use full colormap, but start

res@cnFillOn            = True         ; Turn on contour fill
res@cnLinesOn           = False        ; Turn off contour lines
res@cnLineLabelsOn      = False        ; Turn off contour line labels
res@lbLabelAutoStride   = True         ; Clean up labelbar labels.

res@cnFillMode          = "RasterFill"
res@gsnAddCyclic = False

res@mpMinLatF             = 37.
res@mpMaxLatF             = 49.
res@mpMinLonF             = 278.
res@mpMaxLonF             = 294.

res@gsnLeftString="Population"
res@gsnRightString="#/gridbox (x1000)"
  res@mpOutlineOn                 = True

  res@mpUSStateLineThicknessF     = 1  ; 2-1/2 times as thick.
  res@mpGeophysicalLineThicknessF = 1

  res@mpOutlineBoundarySets       = "GeophysicalAndUSStates"
  res@mpOutlineSpecifiers         = (/"Land","Conterminous US:states"/)
  ;res@mpMaskOutlineSpecifiers     = (/"water"/)

res@cnLevelSelectionMode = "ExplicitLevels"                     ; set explicit contour levels
res@cnLevels    = (/ 1,5,10,25,50,75,100,150,200,250,300,400,500,600,700,800/) ; set levels

map = gsn_csm_contour_map_ce(wks,POP(:,:),res)

end
