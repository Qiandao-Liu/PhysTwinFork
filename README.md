### Setup
#### 🐧Linux Setup for RTX 30 & 40 Series (RTX 4090)
```
# Here we use cuda-12.1
export PATH={YOUR_DIR}/cuda/cuda-12.1/bin:$PATH
export LD_LIBRARY_PATH={YOUR_DIR}/cuda/cuda-12.1/lib64:$LD_LIBRARY_PATH
# Create conda environment
conda create -y -n phystwin python=3.10
conda activate phystwin

# Install the packages
# If you only want to explore the interactive playground, you can skip installing Trellis, Grounding-SAM-2, RealSense, and SDXL.
bash ./env_install/env_install.sh

# Download the necessary pretrained models for data processing
bash ./env_install/download_pretrained_models.sh
```


#### 🐧Linux Setup for RTX 50 Series (RTX 50XX + CUDA 12.8 + Python 3.10)
```
# Here we use CUDA 12.8
export PATH={YOUR_DIR}/cuda/bin:$PATH
export LD_LIBRARY_PATH={YOUR_DIR}/cuda/lib64:$LD_LIBRARY_PATH
export CUDA_HOME={YOUR_DIR}/cuda

# Create conda environment
conda create -y -n phystwin python=3.10
conda activate phystwin

# Forcefully create a symbolic soft link between system libstdc++.so.6 and conda environment libstdc++.so.6 e.g. `ln -sf /usr/lib/x86_64-linux-gnu/libstdc++.so.6
# Install the packages
chmod +x env_install/post_patch_fixups.sh
bash ./env_install/50xx_env_install.sh

# Varify env changes
python scripts/verify_env.py

# Download the necessary pretrained models for data processing
bash ./env_install/download_pretrained_models.sh
```

### Download the PhysTwin Data
Download the original data, processed data, and results into the project's root folder. (The following sections will explain how to process the raw observations and obtain the training results.)
- [data](https://drive.google.com/file/d/1A6X7X6yZFYJ8oo6Bd5LLn-RldeCKJw5Z/view?usp=sharing): this includes the original data for different cases and the processed data for quick run. The different case_name can be found under `different_types` folder.
- [experiments_optimization](https://drive.google.com/file/d/1xKlk3WumFp1Qz31NB4DQxos8jMD_pBAt/view?usp=sharing): results of our first-stage zero-order optimization.
- [experiments](https://drive.google.com/file/d/1hCGzdGlzL4qvZV3GzOCGiaVBshDgFKjq/view?usp=sharing): results of our second-order optimization.
- [gaussian_output](https://drive.google.com/file/d/12EoxhEhE90NMAqLlQoj_zM_C63BOftNW/view?usp=sharing): results of our static gaussian appearance.
- [(optional) additional_data](https://drive.google.com/file/d/1Q9AFDr_yQD-n5YNAe157hViTBC9mo876/view?usp=sharing): data for extra clothing demos not included in the original paper.

### Play with the Interactive Playground
Use the previously constructed PhysTwin to explore the interactive playground. Users can interact with the pre-built PhysTwin using keyboard. The next section will provide a detailed guide on how to construct the PhysTwin from the original data.

![example](./assets/sloth.gif)

Run the interactive playground with our different cases (Need to wait some time for the first usage of interactive playground; Can achieve about 37 FPS using RTX 4090 on sloth case)

```
python interactive_playground.py \
(--inv_ctrl) \
--n_ctrl_parts [1 or 2] \
--case_name [case_name]

# Examples of usage:
python interactive_playground.py --n_ctrl_parts 2 --case_name double_stretch_sloth
python interactive_playground.py --inv_ctrl --n_ctrl_parts 2 --case_name double_lift_cloth_3
```
or in Docker
```
./docker_scripts/run.sh /path/to/data \
                        /path/to/experiments \
                        /path/to/experiments_optimization \
                        /path/to/gaussian_output \
# inside container
conda activate phystwin_env
python interactive_playground.py --inv_ctrl --n_ctrl_parts 2 --case_name double_lift_cloth_3
```

Options: 
-   --inv_ctrl: inverse the control direction
-   --n_ctrol_parts: number of control panel (single: 1, double: 2) 
-   --case_name: case name of the PhysTwin case

### Train the PhysTwin with the data
Use the processed data to train the PhysTwin. Instructions on how to get above `experiments_optimization`, `experiments` and `gaussian_output` (Can adjust the code below to only train on several cases). After this step, you get the PhysTwin that can be used in the interactive playground.
```
# Zero-order Optimization
python script_optimize.py

# First-order Optimization
python script_train.py

# Inference with the constructed models
python script_inference.py

# Train the Gaussian with the first-frame data
bash gs_run.sh
```

### Evaluate the performance of the contructed PhysTwin
To evaluate the performance of the constructed PhysTwin, need to render the images in the original viewpoint (similar logic to interactive playground)
```
# Use LBS to render the dynamic videos (The final videos in ./gaussian_output_dynamic folder)
bash gs_run_simulate.sh
python export_render_eval_data.py
# Get the quantative results
bash evaluate.sh

# Get the qualitative results
bash gs_run_simulate_white.sh
python visualize_render_results.py
```

### Data Processing from Raw Videos
The original data in each case only includes `color`, `depth`, `calibrate.pkl`, `metadata.json`. All other data are processed as below to get, including the projection, tracking and shape priors.
(Note: Be aware of the conflict in the diff-gaussian-rasterization library between Gaussian Splatting and Trellis. For data processing, you don't need to install the gaussian splatting; ignore the last section in env_install.sh)
```
# Process the data
python script_process_data.py

# Further get the data for first-frame Gaussian
python export_gaussian_data.py

# Get human mask data for visualization and rendering evaluation
python export_video_human_mask.py
```

### Control Force Visualization
Visualize the force applied by the hand to the object as inferred from our PhysTwin model, based solely on video data.
```
python visualize_force.py \
--n_ctrl_parts [1 or 2] \
--case_name [case_name]

# Examples of usage:
python visualize_force.py --case_name single_push_rope_1 --n_ctrl_parts 1 
python visualize_force.py --case_name single_clift_cloth_1 --n_ctrl_parts 1    
python visualize_force.py --case_name double_stretch_sloth 
```
The visualziation video is saved under `experiments` folder.

### Material Visualization
Experimental feature to visualize the approximated material from the constructed PhysTwin.
```
python visualize_material.py \
--case_name [case_name]

# Examples of usage:
python visualize_material.py --case_name double_lift_cloth_1
python visualize_material.py --case_name single_push_rope
python visualize_material.py --case_name double_stretch_sloth
```


### Multiple Objects Demos
Try the experimental features for handling collisions among the multiple PhysTwins we construct.

```
# The stuff is deployed in the 'claw_matchine' branch
git pull
git checkout claw_machine

# Play with the examples
python interactive_playground.py --n_ctrl_parts 1 --case_name single_push_rope_1 --n_dup 4
python interactive_playground.py --n_ctrl_parts 2 --case_name double_stretch_sloth --n_dup 2
```

### Follow-up and Potential Collaborations  
If you are interested in collaborating or extending this work for your research, feel free to contact us at `hanxiao.jiang@columbia.edu`.  

### Citation
If you find this repo useful for your research, please consider citing the paper
```
@article{jiang2025phystwin,
    title={PhysTwin: Physics-Informed Reconstruction and Simulation of Deformable Objects from Videos},
    author={Jiang, Hanxiao and Hsu, Hao-Yu and Zhang, Kaifeng and Yu, Hsin-Ni and Wang, Shenlong and Li, Yunzhu},
    journal={ICCV},
    year={2025}
}
```
