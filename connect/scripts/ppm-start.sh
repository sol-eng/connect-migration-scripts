#!/bin/bash -x 

#sudo -u rstudio-pm /opt/rstudio-pm/bin/rstudio-pm --config /etc/rstudio-pm/rstudio-pm.gcfg & 
/opt/rstudio-pm/bin/license-manager activate $RSPM_LICENSE

rm -rf /var/run/rstudio-pm/rstudio-pm.pid

/opt/rstudio-pm/bin/rstudio-pm --config /etc/rstudio-pm/rstudio-pm.gcfg & 

sleep 20

if [ -f /ppm-setup.sh ]; then 
if [[ `rspm list repos | grep repos | awk '{print $1}'` -eq 0 ]]; then 
    bash -x /ppm-setup.sh > /var/log/pm-setup.log
fi
fi

wait 

