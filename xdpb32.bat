#
# xdpb32.bat
# XDPB32 Canvas exporter.
# For a general description, see the program documentation.
#

set UDTHOME=D:\IBM\ud72
set UDTBIN=D:\IBM\ud72\bin
set PATH=%PATH%;%UDTBIN%
set DASU=canvasbatch
set DASP=<<enter your value here for the account in the previous line>>

d:
cd \Datatel\live\apphome
D:\IBM\ud72\bin\udt.exe "XDPB32"