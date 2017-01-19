# Slurm Buildkite Plugin (Alpha)

A [Buildkite](https://buildkite.com/) plugin to run build jobs on super computing clusters using [Slurm](http://slurm.schedmd.com).

## Example

```yml
steps:
  - name: "Slurm"
    plugins:
      slurm:
        TODO: TODO
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
