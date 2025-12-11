// sentinel-translator.js
const net = require('net');
const fs = require('fs');
const path = require('path');

// Parse .env file
function parseEnv(envPath = '.env') {
  const envFile = fs.readFileSync(envPath, 'utf8');
  const env = {};

  envFile.split('\n').forEach(line => {
    line = line.trim();
    if (line && !line.startsWith('#')) {
      const [key, ...valueParts] = line.split('=');
      env[key.trim()] = valueParts.join('=').trim();
    }
  });

  return env;
}

// Build address mapping from .env
function buildMapping(env) {
  const mapping = {};
  const externalHost = env.EXTERNAL_HOST || 'localhost';

  // Primary mapping
  const primaryHost = env.REDIS_PRIMARY_HOST || 'primary';
  const primaryPort = env.REDIS_PRIMARY_PORT || '6379';
  const externalPrimaryPort = env.DOCKER_REDIS_PORT || '6379';
  mapping[`${primaryHost}:${primaryPort}`] = `${externalHost}:${externalPrimaryPort}`;

  // Replica mappings
  const replicaCount = parseInt(env.DOCKER_REDIS_REPLICA_COUNT || '0');
  const replicaPorts = env.DOCKER_REDIS_REPLICA_PORTS || '';
  const [startPort, endPort] = replicaPorts.split('-').map(p => parseInt(p));

  for (let i = 0; i < replicaCount; i++) {
    const replicaHost = `replica-${i + 1}`;
    const internalPort = env.REDIS_REPLICA_PORT || '6379';
    const externalPort = startPort + i;
    mapping[`${replicaHost}:${internalPort}`] = `${externalHost}:${externalPort}`;
  }

  // Sentinel mappings
  const sentinelCount = parseInt(env.DOCKER_REDIS_SENTINEL_COUNT || '0');
  const sentinelPorts = env.DOCKER_REDIS_SENTINEL_PORTS || '';
  const [sentinelStart, sentinelEnd] = sentinelPorts.split('-').map(p => parseInt(p));

  for (let i = 0; i < sentinelCount; i++) {
    const sentinelHost = `sentinel-${i + 1}`;
    const internalPort = env.REDIS_SENTINEL_PORT || '26379';
    const externalPort = sentinelStart + i;
    mapping[`${sentinelHost}:${internalPort}`] = `${externalHost}:${externalPort}`;
  }

  return mapping;
}

// Parse Redis RESP protocol
class RESPParser {
  parse(buffer) {
    const str = buffer.toString('utf8');
    return this.parseValue(str, { pos: 0 });
  }

  parseValue(str, state) {
    const type = str[state.pos];
    state.pos++;

    switch (type) {
      case '+': return this.parseSimpleString(str, state);
      case '-': return this.parseError(str, state);
      case ':': return this.parseInteger(str, state);
      case '$': return this.parseBulkString(str, state);
      case '*': return this.parseArray(str, state);
      default: throw new Error(`Unknown RESP type: ${type}`);
    }
  }

  parseSimpleString(str, state) {
    const end = str.indexOf('\r\n', state.pos);
    const value = str.substring(state.pos, end);
    state.pos = end + 2;
    return { type: 'string', value };
  }

  parseError(str, state) {
    const end = str.indexOf('\r\n', state.pos);
    const value = str.substring(state.pos, end);
    state.pos = end + 2;
    return { type: 'error', value };
  }

  parseInteger(str, state) {
    const end = str.indexOf('\r\n', state.pos);
    const value = parseInt(str.substring(state.pos, end));
    state.pos = end + 2;
    return { type: 'integer', value };
  }

  parseBulkString(str, state) {
    const lengthEnd = str.indexOf('\r\n', state.pos);
    const length = parseInt(str.substring(state.pos, lengthEnd));
    state.pos = lengthEnd + 2;

    if (length === -1) {
      return { type: 'null' };
    }

    const value = str.substring(state.pos, state.pos + length);
    state.pos += length + 2;
    return { type: 'bulk', value };
  }

  parseArray(str, state) {
    const lengthEnd = str.indexOf('\r\n', state.pos);
    const length = parseInt(str.substring(state.pos, lengthEnd));
    state.pos = lengthEnd + 2;

    if (length === -1) {
      return { type: 'null' };
    }

    const array = [];
    for (let i = 0; i < length; i++) {
      array.push(this.parseValue(str, state));
    }
    return { type: 'array', value: array };
  }

  encode(obj) {
    switch (obj.type) {
      case 'string': return `+${obj.value}\r\n`;
      case 'error': return `-${obj.value}\r\n`;
      case 'integer': return `:${obj.value}\r\n`;
      case 'null': return '$-1\r\n';
      case 'bulk': return `$${obj.value.length}\r\n${obj.value}\r\n`;
      case 'array':
        let result = `*${obj.value.length}\r\n`;
        obj.value.forEach(item => {
          result += this.encode(item);
        });
        return result;
      default: throw new Error(`Unknown type: ${obj.type}`);
    }
  }
}

// Translate addresses in RESP response
function translateResponse(respObj, mapping) {
  if (respObj.type === 'bulk') {
    // Check if this looks like a host or IP
    const translated = translateAddress(respObj.value, mapping);
    if (translated !== respObj.value) {
      return { ...respObj, value: translated };
    }
  } else if (respObj.type === 'array') {
    return {
      ...respObj,
      value: respObj.value.map(item => translateResponse(item, mapping))
    };
  }

  return respObj;
}

function translateAddress(addr, mapping) {
  // Direct mapping lookup
  if (mapping[addr]) {
    return mapping[addr];
  }

  // Check if it's just a hostname (we'll need to add default port)
  for (const [internal, external] of Object.entries(mapping)) {
    const [internalHost] = internal.split(':');
    if (addr === internalHost) {
      const [externalHost] = external.split(':');
      return externalHost;
    }
  }

  return addr;
}

// Main translator service
class SentinelTranslator {
  constructor(config) {
    this.config = config;
    this.parser = new RESPParser();
    this.mapping = buildMapping(config.env);

    console.log('Address mapping:');
    Object.entries(this.mapping).forEach(([internal, external]) => {
      console.log(`  ${internal} → ${external}`);
    });
  }

  start() {
    const server = net.createServer(clientSocket => {
      this.handleClient(clientSocket);
    });

    const listenPort = this.config.listenPort || 26379;
    server.listen(listenPort, () => {
      console.log(`\nSentinel translator listening on port ${listenPort}`);
    });
  }

  handleClient(clientSocket) {
    const sentinelHost = this.config.sentinelHost || 'sentinel-1';
    const sentinelPort = this.config.sentinelPort || 26379;

    const sentinelSocket = net.createConnection({
      host: sentinelHost,
      port: sentinelPort
    }, () => {
      console.log(`Connected to sentinel at ${sentinelHost}:${sentinelPort}`);
    });

    // Client → Sentinel (pass through)
    clientSocket.on('data', data => {
      sentinelSocket.write(data);
    });

    // Sentinel → Client (translate addresses)
    sentinelSocket.on('data', data => {
      try {
        const parsed = this.parser.parse(data);
        const translated = translateResponse(parsed, this.mapping);
        const encoded = Buffer.from(this.parser.encode(translated), 'utf8');
        clientSocket.write(encoded);
      } catch (err) {
        console.error('Translation error:', err);
        // If parsing fails, pass through unchanged
        clientSocket.write(data);
      }
    });

    // Handle disconnections
    clientSocket.on('end', () => sentinelSocket.end());
    clientSocket.on('error', err => {
      console.error('Client error:', err.message);
      sentinelSocket.destroy();
    });

    sentinelSocket.on('end', () => clientSocket.end());
    sentinelSocket.on('error', err => {
      console.error('Sentinel error:', err.message);
      clientSocket.destroy();
    });
  }
}

// Main
const env = parseEnv(process.env.ENV_FILE || '.env');

const config = {
  env,
  listenPort: parseInt(process.env.LISTEN_PORT || env.DOCKER_REDIS_SENTINEL_PORTS?.split('-')[0] || 26379),
  sentinelHost: process.env.SENTINEL_HOST || 'sentinel-1',
  sentinelPort: parseInt(process.env.SENTINEL_PORT || env.REDIS_SENTINEL_PORT || 26379)
};

const translator = new SentinelTranslator(config);
translator.start();
