module.exports = {
  apps: [{
    name: 'minecraft-proxy',
    script: './src/index.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '200M',
    env: {
      NODE_ENV: 'production'
    },
    error_file: './logs/error.log',
    out_file: './logs/out.log',
    log_file: './logs/combined.log',
    time: true,
    merge_logs: true,
    max_restarts: 10,
    min_uptime: '10s',
    restart_delay: 4000
  }]
};
