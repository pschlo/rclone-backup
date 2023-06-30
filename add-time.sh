
# by default, the script should not terminate from signals
for ((i=0; i<100; i++)); do
    trap : $i 2>/dev/null && true
done

# append date to input
while IFS= read -r line; do
    printf '%s %s\n' ["$(date +"%Y-%m-%d %T")"] "$line";
done
