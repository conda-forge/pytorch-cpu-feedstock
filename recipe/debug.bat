"C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\gflags.exe" -i python.exe +sls
"C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe" -logo log.txt -g -G -o -xn av python -c "import torch"
