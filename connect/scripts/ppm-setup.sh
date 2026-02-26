#!/bin/bash

set -x 

exec > /var/log/setup-ppm.log
exec 2>&1


# https://docs.posit.co/rspm/admin/getting-started/configuration/#quickstart-cran
rspm create repo --name=cran --description='CRAN packages'
rspm subscribe --repo=cran --source=cran
#rspm sync --type=cran --no-wait

x=`date +%s`
rspm sync 
echo $(( `date +%s`-$x ))

# https://docs.posit.co/rspm/admin/getting-started/configuration/#quickstart-bioconductor
rspm create repo --type=bioconductor --name=bioconductor --description='Bioconductor Packages'
x=`date +%s`
rspm sync --type=bioconductor 
echo $(( `date +%s`-$x ))

# https://docs.posit.co/rspm/admin/getting-started/configuration/#quickstart-pypi-packages
rspm create repo --name=pypi --type=python --description='PyPI packages only'
rspm subscribe --repo=pypi --source=pypi

# https://docs.posit.co/rspm/admin/python-packaging/local-python/#local-python-sources
rspm create source --name=local-python-src --type=local-python
rspm create repo --name=python-repo --type=python --description='Access Python packages (pypi + local)'
rspm subscribe --repo=python-repo --source=local-python-src
rspm subscribe --repo=python-repo --source=pypi

# https://docs.posit.co/rspm/admin/getting-started/configuration/#quickstart-local
rspm create source --name=local-r-src --type=local
rspm create repo --name=local-r --description='Stable releases of our internal R packages'
rspm subscribe --repo=local-r --source=local-r-src

x=`date +%s`
rspm sync --type=pypi
echo $(( `date +%s`-$x ))

