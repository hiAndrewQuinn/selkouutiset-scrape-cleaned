#!/bin/fish

find . -type f -exec sed -i 's/\/q_auto: eco /\/q_auto: eco /g' {} +
find . -type f -exec sed -i 's/q_auto: eco /q_auto: eco /g' {} +
find . -type f -exec sed -i 's/q_auto: eco /q_auto: eco  /g' {} +
find . -type f -exec sed -i 's/q_auto: eco /q_auto: eco/g' {} +
find . -type f -exec sed -i 's/dpr_1.0/dpr_1.0/g' {} +
find . -type f -exec sed -i 's/f_auto\/ fl/f_auto\/fl/g' {} +
