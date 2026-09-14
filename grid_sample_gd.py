import os
# import subprocess
# import numpy as np


sample_ID = list(range(0,49)) # 50 samples including 0 and 49
mesh_script_base = 'mesh_script__automated'
# file_ID = ['','_29layers','_addedInlfationIterations','_addedLEsolve']
# file_ID = ['_noSkewTol']
file_ID = ['_reDimStripDomain_addedsolve']
PW_path = '/opt/software/Pointwise/Pointwise2023.2/pointwise'

def loop_seeds(text_2_replace,mesh_script_file, mesh_script_file_updated):

    # sample_ID already contains the sample numbers (e.g. 0..48).
    # Don't index the list with the values; that breaks if sample_ID changes to non-zero start.
    for sample_num in sample_ID:

        with open(mesh_script_file,'r') as file:
            file_contents = file.read()
            new_text = f"sample_blade{sample_num}"
            updated_contents = file_contents.replace(text_2_replace,new_text)

        with open(mesh_script_file_updated,'w') as file:
            file.write(updated_contents)

        print(f'Generating mesh for sample {sample_num}...\n')
        cmd_PW = f"{PW_path} -b {mesh_script_file_updated}"
        os.system(cmd_PW)
        print('\n')
        print('\n')


for i in file_ID:
    mesh_script_fileID = f'{mesh_script_base}{i}'
    mesh_script_file = f'{mesh_script_fileID}.glf'
    mesh_script_file_updated = f'{mesh_script_fileID}_updated.glf'
    text_2_replace = "sample_blade3"
    loop_seeds(text_2_replace,mesh_script_file,mesh_script_file_updated)