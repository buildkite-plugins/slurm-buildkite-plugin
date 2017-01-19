# Slurm Buildkite Plugin (Alpha)

A [Buildkite](https://buildkite.com/) plugin to run build jobs on super computing clusters using [Slurm](http://slurm.schedmd.com).

## Example

```yml
steps:
  - command: "echo hello world"
    env:
      OMP_NUM_THREADS: 0
      NUM_HYPERTHREADS: 0
    plugins:
      - https://github.com/buildkite/slurm-buildkite-plugin:
          time: "00:05:00"
          nodes: 1
          ntasks-per-node: 16
          modules:
            - "fftw-xl/3.3.4"
            - "vlsci"
```

## Configuring

TODO

## Options

TODO

## Roadmap

* Support configuring the sbatch command via plugin options
* Copy the Buildkite ENV to the command script env
* Artifact downloading from the login node

## License

MIT (see [LICENSE](LICENSE))
