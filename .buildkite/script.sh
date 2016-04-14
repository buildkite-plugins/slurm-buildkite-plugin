#!/bin/bash

echo -e '#!/bin/bash\nhostname' > run.sh
chmod +x run.sh

ssh $SUPERCLUSTER_LOGIN_HOST 'bash -s' < ./run.sh

echo "Hello World!"
