#!/usr/bin/env bash
#
# Purpose:
# provides gcp compute/instance asset inventory including machine type and RAM in .csv report files per project in ./scans directory
#
# Usage:
#
# Single Project
# for i in my-project123; do ./gcp-project-compute-asset-inventory.sh $i; done
#
# Multiple Projects
# for i in my-project123 my-project456; do ./gcp-project-compute-asset-inventory.sh $i; done
#
# Separate projects .csv format results are in the ./scans dir i.e.:
# cat ./scans/myproject-compute_node_metadata.csv
# Instance Name,Zone,Machine Type,vCPU Count,Total Memory (MB),Labels,Tags
# gke-myproject-compute-optimized-331ebceb-cfjd,us-central1-c,https://www.googleapis.com/compute/v1/projects/myproject/zones/us-central1-c/machineTypes/c2-standard-8,8,32768,application=gke;automated=true;env=p;goog-gke-node=;review=prod,gke-myproject-0032007a-node;istio
# gke-myproject-compute-optimized-331ebceb-tr5k,us-central1-c,https://www.googleapis.com/compute/v1/projects/myproject/zones/us-central1-c/machineTypes/c2-standard-8,8,32768,application=gke;automated=true;env=p;goog-gke-node=;review=prod,gke-myproject-0032007a-node;istio
# gke-myproject-compute-optimized-7ad91b1c-dsro,us-central1-f,https://www.googleapis.com/compute/v1/projects/myproject/zones/us-central1-f/machineTypes/c2-standard-8,8,32768,application=gke;automated=true;env=p;goog-gke-node=;review=prod,gke-myproject-0032007a-node;istio
# ...
# 
# For each project the term out will show the totals for the node hardware the totals are obviously not the same data format as the .csv data this is why it is separate--could be refactored to dump to .csv if desired too.
# I.e.:
# Now performing GCP Compute Asset Inventory on Project: my-project-123
# 
# ================================
# Total vCPU count: 1512
# Total memory (MB): 12091392
# ================================
# Total machine-type:
#    9 c2-standard-8
#   90 e2-highmem-16
# ================================
#
# Note there is also the 'gcloud asset search-all-resources' alternative option, but this command does NOT have all of the compute node metadata we would want--it is included here for reference
# for project_id in $project_list; do
#     echo "initiating scan for Project: $project_id and creating results file ./scans/${project_id}-gloud-asset-search-all-resources.csv"
#     gcloud asset search-all-resources --scope "projects/$project_id" --asset-types='compute.googleapis.com/instance' --sort-by 'assetType' --read-mask='*' --format='csv(additionalAttributes.machineType, location, folders, assetType.basename(), name.basename(), labels, organization, state)' > "./scans/${project_id}-gloud-asset-search-all-resources.csv"
# done

# Set the GCP project ID
PROJECT_ID="$1"

echo -e "\nNow performing GCP Compute Asset Inventory on Project: $PROJECT_ID\n"

# Get a list of all the compute instances in the project
instances=$(gcloud compute instances list --project $PROJECT_ID --format="csv[no-heading](name,zone)")

# Initialize variables for the total vCPU and memory count
total_vcpu=0
total_memory=0

# Initialize an array to hold the results
results=()

# Loop through each instance and gather the required metadata
for instance in $instances
do
  name=$(echo $instance | cut -d ',' -f 1)
  zone=$(echo $instance | cut -d ',' -f 2)

  # Get the machine type for the instance
  # Note that we need the whole machineType--i.e.: https://www.googleapis.com/compute/v1/projects/myproject/zones/us-central1-c/machineTypes/c2-standard-8
  # else future logic doesnt work TL;DR we cannot use the below because we need the full URI to query additional steps
  #machine_type=$(gcloud compute instances describe $name --zone $zone --project $PROJECT_ID --format="csv[no-heading](machineType)" | awk -F "machineTypes/" '{print $2}')
  machine_type=$(gcloud compute instances describe $name --zone $zone --project $PROJECT_ID --format="csv[no-heading](machineType)")

  # Get the vCPU count for the instance
  vcpu=$(gcloud compute machine-types describe $machine_type --project $PROJECT_ID --format="csv[no-heading](guestCpus)")

  # Get the total memory for the instance
  memory=$(gcloud compute machine-types describe $machine_type --project $PROJECT_ID --format="csv[no-heading](memoryMb)")

  # Get the instance labels and tags, handling cases where they are missing
  labels=$(gcloud compute instances describe $name --zone $zone --project $PROJECT_ID --format="csv[no-heading](labels)" || echo "None")
  tags=$(gcloud compute instances describe $name --zone $zone --project $PROJECT_ID --format="csv[no-heading](tags.items)" || echo "None")

  # Add the metadata to the results array
  results+=("$name,$zone,$machine_type,$vcpu,$memory,$labels,$tags")

  # Update the total vCPU and memory count
  total_vcpu=$((total_vcpu + vcpu))
  total_memory=$((total_memory + memory))
done

# Print the results to a csv file
mkdir -p ./scans
echo "Instance Name,Zone,Machine Type,vCPU Count,Total Memory (MB),Labels,Tags" > "./scans/${PROJECT_ID}-compute_node_metadata.csv"
printf "%s\n" "${results[@]}" | sort >> "./scans/${PROJECT_ID}-compute_node_metadata.csv"

# get machine_type summary/count explicitly for the total machine_type count
machine_type_map=$(gcloud asset search-all-resources --scope="projects/$PROJECT_ID" --asset-types='compute.googleapis.com/instance' --format='csv(additionalAttributes.machineType)' | sort | uniq -c | grep -v 'machine_type')

# Print the total vCPU and memory count to the console not the .csv file because the data types don't match
echo "================================"
echo "Total vCPU count: $total_vcpu"
echo "Total memory (MB): $total_memory"
echo "================================"
echo -e "Total machine-type:\n$machine_type_map"
echo -e "================================\n"

echo -e "\nscan results are in ./scans/${PROJECT_ID}-compute_node_metadata.csv\n"
ls -lat ./scans/*.csv
echo ""

