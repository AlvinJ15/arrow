#!/usr/bin/env bash

# This script uses the otel span data placed in otel/out/out.json
# The otel/out/out.json is generated running arrowbenchs with OTEL enabled and jaeger exporter configured
# Clone the quenta repository
git clone https://github.com/voltrondata/quenta.git --recursive
find_in_conda_env(){
    conda env list | grep "${@}" >/dev/null 2>/dev/null
}

# Create a conda env for build and execute the quenta tool
if find_in_conda_env ".*quenta-env.*" ; then
   conda activate quenta-env
else
  conda create -y -c conda-forge -n quenta-env rust
  conda activate quenta-env
  conda install -y -c conda-forge protobuf
  conda install -y -c anaconda graphviz
fi

# Execute quenta and parse otel data to a tracing graph
cd quenta
mkdir output_tracing
cargo r -- file ../../out/out.json export trace-graph json output_tracing
trace_file=$(ls -S output_tracing | head -1)
cd ..

# Get the grafana flamegraph plugin from a public repository, and build it
if cd grafana-d3-flamegraph; then
  git pull;
else
  git clone https://github.com/AlvinJ15/grafana-d3-flamegraph.git grafana-d3-flamegraph;
  cd grafana-d3-flamegraph;
  yarn install;
  yarn add --dev @types/d3-tip
  yarn add --dev @js-temporal/polyfill;
fi

# Use the largest tracing graph for generate the flamegraph
cp ../quenta/output_tracing/$trace_file src/trace.json
yarn dev;

# Start the container
docker run -d -p 3000:3000 \
-v "$(pwd)"/../../grafana-otel:/var/lib/grafana/plugins \
-v "$(pwd)"/../../grafana-otel/provisioning:/etc/grafana/provisioning \
-v "$(pwd)"/../../grafana-otel/dashboards:/var/lib/grafana/dashboards \
--name=grafana-flamegraph grafana/grafana:7.0.0
