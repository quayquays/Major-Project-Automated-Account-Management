#!/bin/bash

echo "Setting up dormant.conf file, Please wait a moment"

#see if the dormant.conf file exist first if not then proceed to create one

if [[ ! -f /etc/dormant.conf ]]; then
    echo "Generating default config template at /etc/dormant.conf"
    
    # create the template 
    cat <<EOL | sudo tee /etc/dormant.conf > /dev/null
#configuration file of dormant accounts ( USER and SERVICES )

# Specify the number of days for dormant user accounts
DORMANT_USERACCOUNT_DURATION=70  #Example: 70 days

# Specify the number of days for dormant service accounts
DORMANT_SERVICEACCOUNT_DURATION=30  #Example: 30 days
EOL

    echo "dormant.conf file generated at  /etc/dormant.conf"
else
    echo "/etc/dormant.conf already exists. Skipping overwrite."
fi

echo "Setup complete! edit config at /etc/dormant.conf"
