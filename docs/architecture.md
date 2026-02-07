# Architecture Specification

**Version**: 1.0.0
**Last Updated**: 2024-02-07
**Status**: Implementation Complete

## Table of Contents

- [Overview](#overview)
- [System Architecture](#system-architecture)
- [Component Specifications](#component-specifications)
- [Data Flow](#data-flow)
- [Service Contracts](#service-contracts)
- [State Machines](#state-machines)
- [Failure Modes](#failure-modes)
- [Deployment Models](#deployment-models)
- [Security Architecture](#security-architecture)
- [Performance Characteristics](#performance-characteristics)
- [Scalability & Limitations](#scalability--limitations)

## Overview

This document provides the technical architecture specification for the PostgreSQL Backup & Restore Verification Railway template. The system provides automated, verified database backups to S3-compatible storage.

### Design Principles

1. **Fail-Fast**: Invalid configuration or unrecoverable errors cause immediate exit with clear messages
2. **Idempotent**: All operations can be safely retried
3. **No Side Effects**: Verification never impacts production database
4. **Observable**: All operations logged with timestamps and context
5. **Portable**: Works with any S3-compatible storage and PostgreSQL 12+
6. **Stateless**: Services maintain no persistent state (all state in S3/database)

### Key Design Decisions

| Decision | Rationale | Trade-offs |
|----------|-----------|------------|
| pg_dump (logical backup) | Cross-version compatibility, human-readable, selective restore | Slower than physical backup; requires online database |
| Bash scripting | No dependencies, easy to debug, standard tool | Less robust than higher-level languages |
| AWS CLI for S3 | Universal S3 compatibility, well-tested | Larger Docker image |
| Separate verify service | Optional deployment, no production impact | Additional service to manage |
| Environment variables | Railway-native, secure, standard | No hierarchical config |
| SQL dump format | Human-readable, portable, compressible | Larger than binary; slower to restore |

## System Architecture

### High-Level Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                      Railway Project / Deployment                   │
│                                                                     │
│  ┌─────────────────┐      ┌──────────────────┐                    │
│  │   PostgreSQL    │      │  Backup Service   │                    │
│  │    Database     │      │                   │                    │
│  │                 │◄─────┤  - pg_dump        │                    │
│  │  - Primary DB   │ read │  - gzip           │                    │
│  │  - Production   │      │  - aws s3 cp      │                    │
│  │    Data         │      │  - retention mgmt │                    │
│  └────────┬────────┘      └─────────┬──────────┘                   │
│           │                          │                              │
│           │                          │                              │
│           │               ┌──────────▼──────────┐                  │
│           │               │   S3-Compatible     │                  │
│           │               │     Storage         │                  │
│           │               │                     │                  │
│           │               │  backup_*.sql.gz    │                  │
│           │               └──────────┬──────────┘                  │
│           │                          │                              │
│           │                          │                              │
│  ┌────────▼────────┐      ┌─────────▼──────────┐                  │
│  │   Temporary     │      │  Verify Service     │                  │
│  │   Databases     │◄─────┤                    │                  │
│  │                 │write │  - aws s3 cp        │                  │
│  │  verify_*       │      │  - gunzip           │                  │
│  │  (auto-cleanup) │      │  - psql restore     │                  │
│  └─────────────────┘      │  - verification     │                  │
│                            │  - cleanup          │                  │
│                            └─────────────────────┘                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

External Dependencies:
  - S3-Compatible Storage (AWS S3, Backblaze B2, MinIO, etc.)
  - Internet connectivity for S3 access
  - PostgreSQL client tools (bundled in containers)
```

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         Backup Service                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐      │
│  │    Config    │──▶│   Validator  │──▶│ Health Check │      │
│  │   Loader     │   │              │   │              │      │
│  └──────────────┘   └──────────────┘   └──────────────┘      │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐      │
│  │   pg_dump    │──▶│     gzip     │──▶│   AWS CLI    │      │
│  │   Process    │   │  Compressor  │   │  S3 Upload   │      │
│  └──────────────┘   └──────────────┘   └──────────────┘      │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐                          │
│  │  Retention   │   │   Scheduler  │                          │
│  │   Manager    │   │  (sleep loop)│                          │
│  └──────────────┘   └──────────────┘                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Verify Service                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐      │
│  │    Config    │──▶│   Validator  │──▶│Backup Finder │      │
│  │   Loader     │   │              │   │  (S3 list)   │      │
│  └──────────────┘   └──────────────┘   └──────────────┘      │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐      │
│  │   AWS CLI    │──▶│    gunzip    │──▶│     psql     │      │
│  │  S3 Download │   │ Decompressor │   │   Restore    │      │
│  └──────────────┘   └──────────────┘   └──────────────┘      │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐      │
│  │ Verification │   │   Cleanup    │   │   Scheduler  │      │
│  │   Queries    │   │   Manager    │   │ (sleep loop) │      │
│  └──────────────┘   └──────────────┘   └──────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Component Specifications

### Backup Service

#### Inputs
- **Environment Variables**: Configuration (DATABASE_URL, S3_*, BACKUP_*)
- **PostgreSQL Database**: Source data
- **S3 Storage**: Existing backups (for retention management)

#### Outputs
- **S3 Backup Files**: `s3://bucket/prefix/backup_YYYYMMDD_HHMMSS.sql.gz`
- **Logs**: stdout/stderr with operation details
- **Health Check**: HTTP endpoint (optional, for monitoring)

#### Processing Steps

```
┌─────────────────────────────────────────────────────────┐
│ 1. INITIALIZATION                                       │
│    - Load environment variables                         │
│    - Validate required variables                        │
│    - Parse DATABASE_URL                                 │
│    - Configure AWS CLI                                  │
│    - Log configuration (without secrets)                │
│    EXIT CODE 1 if invalid                               │
└─────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────┐
│ 2. HEALTH CHECK                                         │
│    - Test database connectivity (pg_isready)            │
│    - Test S3 connectivity (aws s3 ls)                   │
│    CONTINUE if both pass, LOG ERROR and CONTINUE        │
└─────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────┐
│ 3. BACKUP LOOP (infinite)                               │
│    ┌─────────────────────────────────────────────────┐ │
│    │ 3a. CREATE BACKUP                                │ │
│    │     - Generate timestamp                         │ │
│    │     - Run pg_dump | gzip > /tmp/backup_*.sql.gz │ │
│    │     - Verify file is not empty                   │ │
│    │     - Log file size                              │ │
│    │     ERROR: Log and skip to sleep                 │ │
│    └─────────────────────────────────────────────────┘ │
│          │                                               │
│          ▼                                               │
│    ┌─────────────────────────────────────────────────┐ │
│    │ 3b. UPLOAD TO S3                                 │ │
│    │     - aws s3 cp /tmp/backup_*.sql.gz s3://...   │ │
│    │     - Verify upload success                      │ │
│    │     - Log S3 key                                 │ │
│    │     ERROR: Log and skip to cleanup              │ │
│    └─────────────────────────────────────────────────┘ │
│          │                                               │
│          ▼                                               │
│    ┌─────────────────────────────────────────────────┐ │
│    │ 3c. CLEANUP LOCAL FILE                           │ │
│    │     - rm /tmp/backup_*.sql.gz                    │ │
│    └─────────────────────────────────────────────────┘ │
│          │                                               │
│          ▼                                               │
│    ┌─────────────────────────────────────────────────┐ │
│    │ 3d. RETENTION MANAGEMENT                         │ │
│    │     - List all backups in S3                     │ │
│    │     - Calculate cutoff date                      │ │
│    │     - Delete backups older than retention        │ │
│    │     - Log number deleted                         │ │
│    │     ERROR: Log warning and continue              │ │
│    └─────────────────────────────────────────────────┘ │
│          │                                               │
│          ▼                                               │
│    ┌─────────────────────────────────────────────────┐ │
│    │ 3e. SLEEP                                        │ │
│    │     - sleep $BACKUP_INTERVAL                     │ │
│    │     - Log next backup time                       │ │
│    └─────────────────────────────────────────────────┘ │
│          │                                               │
│          └───────────────────┐                           │
│                              ▼                           │
│                        (repeat loop)                     │
└─────────────────────────────────────────────────────────┘
```

#### Error Handling

| Error Type | Severity | Action | Exit Code |
|------------|----------|--------|-----------|
| Missing env var | FATAL | Exit immediately | 1 |
| Invalid DATABASE_URL | FATAL | Exit immediately | 1 |
| Database unreachable | ERROR | Log, skip backup, continue | 0 (continues) |
| pg_dump failure | ERROR | Log, skip backup, continue | 0 (continues) |
| Empty backup file | ERROR | Log, skip upload, continue | 0 (continues) |
| S3 upload failure | ERROR | Log, skip backup, continue | 0 (continues) |
| Retention cleanup failure | WARNING | Log, continue | 0 (continues) |
| SIGTERM | INFO | Graceful shutdown | 0 |

### Verify Service

#### Inputs
- **Environment Variables**: Configuration (DATABASE_URL, S3_*, VERIFY_*)
- **S3 Storage**: Backup files to verify
- **PostgreSQL Server**: Target for temporary databases

#### Outputs
- **Temporary Databases**: `verify_YYYYMMDD_HHMMSS` (created and deleted)
- **Logs**: stdout/stderr with verification results
- **Exit Status**: 0 for ongoing operation, 1 for fatal error

#### Processing Steps

```
┌─────────────────────────────────────────────────────────┐
│ 1. INITIALIZATION                                       │
│    - Load environment variables                         │
│    - Validate required variables                        │
│    - Parse DATABASE_URL                                 │
│    - Configure AWS CLI                                  │
│    EXIT CODE 1 if invalid                               │
└─────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────┐
│ 2. VERIFICATION LOOP (infinite)                         │
│    ┌─────────────────────────────────────────────────┐ │
│    │ 2a. FIND BACKUP                                  │ │
│    │     - aws s3 ls s3://bucket/prefix/              │ │
│    │     - Select latest or specific backup           │ │
│    │     ERROR: Log and skip to sleep                 │ │
│    └─────────────────────────────────────────────────┘ │
│          │                                               │
│          ▼                                               │
│    ┌─────────────────────────────────────────────────┐ │
│    │ 2b. DOWNLOAD BACKUP                              │ │
│    │     - aws s3 cp s3://... /tmp/backup_*.sql.gz   │ │
│    │     - Verify file is not empty                   │ │
│    │     - Log file size                              │ │
│    │     ERROR: Log and skip to sleep                 │ │
│    └─────────────────────────────────────────────────┘ │
│          │                                               │
│          ▼                                               │
│    ┌─────────────────────────────────────────────────┐ │
│    │ 2c. CREATE TEMPORARY DATABASE                    │ │
│    │     - Generate unique name (verify_YYYYMMDD_*)   │ │
│    │     - psql CREATE DATABASE verify_*              │ │
│    │     ERROR: Log and skip to cleanup               │ │
│    └─────────────────────────────────────────────────┘ │
│          │                                               │
│          ▼                                               │
│    ┌─────────────────────────────────────────────────┐ │
│    │ 2d. RESTORE BACKUP                               │ │
│    │     - gunzip -c backup_*.sql.gz | psql verify_* │ │
│    │     - Capture errors (non-fatal)                 │ │
│    │     ERROR: Log and mark failed                   │ │
│    └─────────────────────────────────────────────────┘ │
│          │                                               │
│          ▼                                               │
│    ┌─────────────────────────────────────────────────┐ │
│    │ 2e. RUN VERIFICATION QUERIES                     │ │
│    │     - Built-in queries (table count, etc.)       │ │
│    │     - Custom queries from test-queries.sql       │ │
│    │     - Log query results                          │ │
│    │     ERROR: Log warning, continue                 │ │
│    └─────────────────────────────────────────────────┘ │
│          │                                               │
│          ▼                                               │
│    ┌─────────────────────────────────────────────────┐ │
│    │ 2f. CLEANUP                                      │ │
│    │     - rm /tmp/backup_*.sql*                      │ │
│    │     - psql DROP DATABASE verify_*                │ │
│    │     - Log verification result (SUCCESS/FAILURE)  │ │
│    └─────────────────────────────────────────────────┘ │
│          │                                               │
│          ▼                                               │
│    ┌─────────────────────────────────────────────────┐ │
│    │ 2g. SLEEP                                        │ │
│    │     - sleep $VERIFY_INTERVAL                     │ │
│    │     - Log next verification time                 │ │
│    └─────────────────────────────────────────────────┘ │
│          │                                               │
│          └───────────────────┐                           │
│                              ▼                           │
│                        (repeat loop)                     │
└─────────────────────────────────────────────────────────┘
```

#### Error Handling

| Error Type | Severity | Action | Exit Code |
|------------|----------|--------|-----------|
| Missing env var | FATAL | Exit immediately | 1 |
| Invalid DATABASE_URL | FATAL | Exit immediately | 1 |
| No backups in S3 | ERROR | Log, skip verification, continue | 0 (continues) |
| Download failure | ERROR | Log, skip verification, continue | 0 (continues) |
| Cannot create DB | ERROR | Log, skip verification, continue | 0 (continues) |
| Restore failure | ERROR | Log as FAILED verification, cleanup, continue | 0 (continues) |
| Verification query failure | WARNING | Log, continue other queries | 0 (continues) |
| Cleanup failure | WARNING | Log, continue | 0 (continues) |
| SIGTERM | INFO | Cleanup, graceful shutdown | 0 |

## Data Flow

### Backup Data Flow

```
┌──────────────┐
│  PostgreSQL  │
│   Database   │
└──────┬───────┘
       │
       │ 1. pg_dump reads data
       │    (SQL commands)
       ▼
┌──────────────┐
│   pg_dump    │
│   Process    │
└──────┬───────┘
       │
       │ 2. Pipe to gzip
       │    (uncompressed SQL)
       ▼
┌──────────────┐
│     gzip     │
│  Compressor  │
└──────┬───────┘
       │
       │ 3. Write to disk
       │    (compressed SQL)
       ▼
┌──────────────────────┐
│  /tmp/backup_*.gz    │
│  (temporary file)    │
└──────┬───────────────┘
       │
       │ 4. Upload via AWS CLI
       │    (HTTPS/TLS)
       ▼
┌──────────────────────┐
│    S3 Storage        │
│  backup_*.sql.gz     │
└──────────────────────┘
       │
       │ 5. Cleanup local
       │    (rm /tmp/backup_*)
       ▼
┌──────────────────────┐
│   Local file deleted │
└──────────────────────┘

Data Size Flow:
  Database: 1000 MB (uncompressed)
  ↓ pg_dump output: ~1000 MB (SQL text)
  ↓ gzip compression: ~300 MB (typical 70% compression)
  ↓ S3 upload: 300 MB
  ↓ Disk cleanup: 0 MB (local file deleted)
```

### Restore Verification Data Flow

```
┌──────────────────────┐
│    S3 Storage        │
│  backup_*.sql.gz     │
└──────┬───────────────┘
       │
       │ 1. Download via AWS CLI
       │    (HTTPS/TLS)
       ▼
┌──────────────────────┐
│  /tmp/backup_*.gz    │
│  (temporary file)    │
└──────┬───────────────┘
       │
       │ 2. Decompress
       │    (gunzip -c)
       ▼
┌──────────────────────┐
│     gunzip           │
│   (streaming)        │
└──────┬───────────────┘
       │
       │ 3. Pipe to psql
       │    (uncompressed SQL)
       ▼
┌──────────────────────┐
│       psql           │
│    (restore)         │
└──────┬───────────────┘
       │
       │ 4. Write to database
       │    (SQL execution)
       ▼
┌──────────────────────┐
│   verify_* DB        │
│  (temporary)         │
└──────┬───────────────┘
       │
       │ 5. Run verification queries
       │    (SELECT queries)
       ▼
┌──────────────────────┐
│ Verification Results │
│   (logged)           │
└──────────────────────┘
       │
       │ 6. Cleanup
       │    (DROP DATABASE, rm files)
       ▼
┌──────────────────────┐
│  All resources       │
│    deleted           │
└──────────────────────┘

Data Size Flow:
  S3 download: 300 MB (compressed)
  ↓ Temporary disk: 300 MB (compressed file)
  ↓ Decompression: ~1000 MB (streamed, not stored)
  ↓ Database restore: 1000 MB (in temp database)
  ↓ Cleanup: 0 MB (all deleted)
```

## Service Contracts

### Backup Service Contract

**Service Name**: `postgres-backup`

**Container Image**: Built from `services/backup/Dockerfile`

**Required Environment Variables**:
```bash
DATABASE_URL           # postgresql://user:pass@host:port/db
S3_ENDPOINT           # https://s3.amazonaws.com
S3_BUCKET             # bucket-name
S3_ACCESS_KEY_ID      # access-key
S3_SECRET_ACCESS_KEY  # secret-key
```

**Optional Environment Variables**:
```bash
BACKUP_INTERVAL=3600           # seconds
BACKUP_RETENTION_DAYS=7        # days
S3_REGION=us-east-1           # region
BACKUP_PREFIX=postgres-backups # S3 prefix
COMPRESSION_LEVEL=6            # 1-9
```

**Health Check**:
```bash
Command: /app/healthcheck.sh
Interval: 5m
Timeout: 30s
Retries: 3
```

**Resource Requirements**:
```yaml
Memory: 256MB minimum, 512MB recommended
CPU: 0.5 cores minimum, 1 core recommended
Disk: 2× largest expected backup size
Network: Internet access to S3 endpoint
```

**Logging**:
- **Format**: Plain text, one line per event
- **Timestamp**: ISO 8601 format (YYYY-MM-DDTHH:MM:SSZ)
- **Levels**: INFO, WARNING, ERROR
- **Destination**: stdout/stderr

**Exit Codes**:
- `0`: Normal operation (infinite loop until SIGTERM)
- `1`: Fatal error (invalid configuration)

**Signal Handling**:
- `SIGTERM`: Graceful shutdown (finish current operation, exit)
- `SIGINT`: Graceful shutdown (same as SIGTERM)

### Verify Service Contract

**Service Name**: `postgres-verify`

**Container Image**: Built from `services/verify/Dockerfile`

**Required Environment Variables**:
```bash
DATABASE_URL           # postgresql://user:pass@host:port/postgres
S3_ENDPOINT           # https://s3.amazonaws.com
S3_BUCKET             # bucket-name
S3_ACCESS_KEY_ID      # access-key
S3_SECRET_ACCESS_KEY  # secret-key
```

**Optional Environment Variables**:
```bash
VERIFY_INTERVAL=86400          # seconds
S3_REGION=us-east-1           # region
BACKUP_PREFIX=postgres-backups # S3 prefix
VERIFY_LATEST=true            # true/false
VERIFY_BACKUP_FILE=           # specific backup file
```

**Custom Verification Queries**:
- File: `/app/test-queries.sql`
- Format: Standard PostgreSQL SQL
- Errors: Non-fatal, logged as warnings

**Resource Requirements**:
```yaml
Memory: 512MB minimum, 1GB recommended
CPU: 0.5 cores minimum, 1 core recommended
Disk: 4× backup size (compressed + decompressed + temp DB)
Network: Internet access to S3 endpoint
```

**Database Permissions Required**:
```sql
CREATEDB    -- To create temporary databases
```

**Logging**:
- **Format**: Plain text, one line per event
- **Timestamp**: ISO 8601 format
- **Levels**: INFO, WARNING, ERROR
- **Destination**: stdout/stderr

**Exit Codes**:
- `0`: Normal operation (infinite loop until SIGTERM)
- `1`: Fatal error (invalid configuration)

**Signal Handling**:
- `SIGTERM`: Graceful shutdown (cleanup temp DB, exit)
- `SIGINT`: Graceful shutdown (same as SIGTERM)

## State Machines

### Backup Service State Machine

```
┌─────────────┐
│   STARTUP   │
└──────┬──────┘
       │
       │ Validate config
       │
       ▼
┌─────────────┐──────────┐
│    IDLE     │          │ On interval
└──────┬──────┘          │
       │                 │
       │ Interval        │
       │ elapsed         │
       ▼                 │
┌─────────────┐          │
│  BACKING_UP │          │
└──────┬──────┘          │
       │                 │
       │ Success         │
       ▼                 │
┌─────────────┐          │
│  UPLOADING  │          │
└──────┬──────┘          │
       │                 │
       │ Success         │
       ▼                 │
┌─────────────┐          │
│  CLEANING   │          │
│  RETENTION  │          │
└──────┬──────┘          │
       │                 │
       │ Complete        │
       ├─────────────────┘
       │
       │ On error: log, return to IDLE
       │
       ▼
   (SIGTERM) ──▶ EXIT

States:
  STARTUP: Load and validate configuration
  IDLE: Waiting for next backup interval
  BACKING_UP: Running pg_dump and gzip
  UPLOADING: Uploading to S3
  CLEANING: Deleting old backups
  EXIT: Graceful shutdown
```

### Verify Service State Machine

```
┌─────────────┐
│   STARTUP   │
└──────┬──────┘
       │
       │ Validate config
       │
       ▼
┌─────────────┐──────────┐
│    IDLE     │          │ On interval
└──────┬──────┘          │
       │                 │
       │ Interval        │
       │ elapsed         │
       ▼                 │
┌─────────────┐          │
│ DOWNLOADING │          │
└──────┬──────┘          │
       │                 │
       │ Success         │
       ▼                 │
┌─────────────┐          │
│  CREATING   │          │
│   TEMP_DB   │          │
└──────┬──────┘          │
       │                 │
       │ Success         │
       ▼                 │
┌─────────────┐          │
│  RESTORING  │          │
└──────┬──────┘          │
       │                 │
       │ Success         │
       ▼                 │
┌─────────────┐          │
│  VERIFYING  │          │
└──────┬──────┘          │
       │                 │
       │ Complete        │
       ▼                 │
┌─────────────┐          │
│  CLEANUP    │          │
└──────┬──────┘          │
       │                 │
       │ Complete        │
       ├─────────────────┘
       │
       │ On error: cleanup, log, return to IDLE
       │
       ▼
   (SIGTERM) ──▶ EXIT

States:
  STARTUP: Load and validate configuration
  IDLE: Waiting for next verification interval
  DOWNLOADING: Downloading backup from S3
  CREATING_TEMP_DB: Creating temporary database
  RESTORING: Restoring backup to temp database
  VERIFYING: Running verification queries
  CLEANUP: Deleting temp database and files
  EXIT: Graceful shutdown
```

## Failure Modes

### Failure Mode Analysis

| Component | Failure | Detection | Impact | Recovery | MTTR |
|-----------|---------|-----------|--------|----------|------|
| Backup Service | Container crash | Railway monitoring | No new backups | Auto-restart | <1 min |
| Backup Service | Database unreachable | pg_isready check | Backup skipped | Retry next interval | <1 hr |
| Backup Service | S3 unreachable | aws s3 ls check | Backup skipped | Retry next interval | <1 hr |
| Backup Service | Disk full | Backup file check | Backup skipped | Manual disk cleanup | <30 min |
| Backup Service | pg_dump failure | Exit code check | Backup skipped | Fix permissions | <15 min |
| Verify Service | Container crash | Railway monitoring | No verification | Auto-restart | <1 min |
| Verify Service | No backups | aws s3 ls check | Verification skipped | Wait for backup | <1 hr |
| Verify Service | Cannot create DB | psql error | Verification skipped | Fix permissions | <15 min |
| Verify Service | Restore failure | psql error | Alert: corrupted backup | Investigate backup | <1 hr |
| S3 Storage | Provider outage | Upload/download failure | Backups queue locally | Wait for provider | varies |
| S3 Storage | Quota exceeded | Upload failure | Backup skipped | Increase quota | <30 min |
| PostgreSQL | Database down | Connection failure | Backup skipped | Fix database | varies |
| PostgreSQL | Disk full | Database error | Backup fails | Free disk space | <30 min |
| Network | Internet loss | Connection timeout | Operations skipped | Restore network | varies |

### Cascading Failure Analysis

**Scenario 1: S3 Provider Outage**
```
S3 Provider Down
  ↓
Backup Upload Fails
  ↓
Local backup file accumulates
  ↓
Potential: Disk fills up
  ↓
Service crashes
  ↓
Mitigation: Monitor disk usage, alert on S3 failures
```

**Scenario 2: Database Disk Full**
```
Database Disk Full
  ↓
Database becomes read-only or crashes
  ↓
Backup service cannot connect
  ↓
Backups fail
  ↓
No alerts if backups already failing
  ↓
Mitigation: Monitor database disk, alert on backup failures
```

**Scenario 3: Corrupted Backups**
```
Silent Database Corruption
  ↓
Backups created with corrupt data
  ↓
Multiple corrupt backups accumulate
  ↓
Verify service detects restore failure
  ↓
Alert: All recent backups may be corrupt
  ↓
Mitigation: Verify service catches early, keep longer retention
```

### Error Budget

**Target SLOs**:
- Backup Success Rate: >99% (allows ~7 failed backups per month if hourly)
- Verify Success Rate: >95% (allows ~1 failed verification per month if daily)
- Mean Time To Detect (MTTD): <15 minutes
- Mean Time To Recover (MTTR): <1 hour

## Deployment Models

### Model 1: All-in-One (Recommended for Small Projects)

```
┌─────────────────────────────────────┐
│         Railway Project             │
│                                     │
│  ┌──────────┐  ┌────────┐  ┌────────┐
│  │PostgreSQL│  │ Backup │  │ Verify │
│  │ Service  │  │Service │  │Service │
│  └──────────┘  └────────┘  └────────┘
└─────────────────────────────────────┘
```

**Pros**:
- Simple setup
- Single Railway project
- Lower cost

**Cons**:
- Verify creates load on production DB server
- All services share resources

**Use Cases**:
- Development/staging environments
- Small production databases (<1GB)
- Solo developers, side projects

### Model 2: Separated Verification (Recommended for Production)

```
┌───────────────────────┐   ┌───────────────────────┐
│  Production Project   │   │   Verify Project      │
│                       │   │                       │
│  ┌──────────┐  ┌────┐│   │  ┌──────────┐  ┌────┐│
│  │PostgreSQL│  │Back││   │  │PostgreSQL│  │Veri││
│  │ Primary  │  │up  ││   │  │  Replica │  │fy  ││
│  └──────────┘  └────┘│   │  └──────────┘  └────┘│
└───────────────────────┘   └───────────────────────┘
```

**Pros**:
- No impact on production database
- Better security (verify doesn't need production access)
- Can test restore to different PostgreSQL version

**Cons**:
- More complex setup
- Higher cost (separate database server)
- Requires read replica or separate database

**Use Cases**:
- Production applications
- Large databases (>10GB)
- High-availability requirements
- Compliance requirements

### Model 3: Multi-Region

```
┌───────────────────┐        ┌───────────────────┐
│   Region 1 (US)   │        │   Region 2 (EU)   │
│                   │        │                   │
│  ┌──────┐  ┌────┐│        │  ┌──────┐  ┌────┐│
│  │  DB  │  │Back││───────▶│  │  DB  │  │Veri││
│  └──────┘  └────┘│   S3   │  └──────┘  └────┘│
└───────────────────┘        └───────────────────┘
```

**Pros**:
- Disaster recovery
- Tests cross-region restore
- Geographic redundancy

**Cons**:
- Most complex
- Highest cost
- Network latency for downloads

**Use Cases**:
- Global applications
- Disaster recovery requirements
- Multi-region compliance

## Security Architecture

### Credential Flow

```
┌──────────────────────┐
│   Railway Console    │
│ (Environment Vars)   │
└──────────┬───────────┘
           │ Encrypted at rest
           │ Encrypted in transit
           ▼
┌──────────────────────┐
│  Railway Runtime     │
│  (Injected at start) │
└──────────┬───────────┘
           │
           ├────────────────┐
           ▼                ▼
┌──────────────┐   ┌──────────────┐
│   Backup     │   │   Verify     │
│   Service    │   │   Service    │
└──────┬───────┘   └──────┬───────┘
       │                   │
       │ Read-only         │ Read-only +
       │ access            │ CREATEDB
       ▼                   ▼
┌──────────────┐   ┌──────────────┐
│  PostgreSQL  │   │      S3      │
└──────────────┘   └──────────────┘
```

### Threat Model

| Threat | Mitigation | Status |
|--------|------------|--------|
| Credentials in logs | Never log secrets, scrub logs | ✅ Implemented |
| Credentials in code | Environment variables only | ✅ Implemented |
| Credentials in repo | .gitignore, no defaults | ✅ Implemented |
| Backup data exposure | S3 encryption, private buckets | ⚠️ User responsibility |
| MITM attacks | HTTPS for S3, SSL for database | ✅ Supported |
| Unauthorized S3 access | IAM policies, bucket policies | ⚠️ User responsibility |
| Temp DB access | Unique names, auto-cleanup | ✅ Implemented |
| Container escape | Minimal privileges, no root | ✅ Implemented |

### Security Best Practices

1. **S3 Bucket Security**:
   - Enable server-side encryption (SSE-S3 or SSE-KMS)
   - Use bucket policies to restrict access
   - Enable versioning for backup protection
   - Enable MFA delete for critical buckets
   - Disable public access

2. **Database Security**:
   - Use SSL/TLS for connections (`?sslmode=require`)
   - Use strong passwords (20+ characters)
   - Rotate credentials every 90 days
   - Use least privilege (SELECT for backup, CREATEDB for verify)
   - Restrict network access by IP when possible

3. **Container Security**:
   - Use official base images (`postgres:16-alpine`)
   - Scan images for vulnerabilities (Trivy in CI)
   - Don't run as root (postgres user)
   - Minimal tools installed
   - No secrets in image layers

4. **Operational Security**:
   - Monitor logs for failed authentications
   - Alert on configuration changes
   - Regular security audits
   - Incident response plan
   - Regular restore drills (verify service)

## Performance Characteristics

### Backup Performance

| Database Size | Dump Time | Compress Time | Upload Time | Total Time | Disk Usage |
|--------------|-----------|---------------|-------------|------------|------------|
| 100 MB | 10s | 5s | 10s | ~30s | 30 MB |
| 1 GB | 2 min | 1 min | 2 min | ~5 min | 300 MB |
| 10 GB | 15 min | 8 min | 10 min | ~35 min | 3 GB |
| 100 GB | 2.5 hr | 1.5 hr | 2 hr | ~6 hr | 30 GB |

**Assumptions**:
- 70% compression ratio (typical)
- 10 Mbps upload speed
- Single-threaded pg_dump
- Standard disk I/O

**Optimization Opportunities**:
- Use `pg_dump --jobs=N` for parallel dumps (large databases)
- Increase compression speed with lower level (trade-off: size)
- Use faster network connection
- Use SSD storage

### Restore Performance

| Backup Size (compressed) | Download | Decompress | Restore | Verify | Total |
|------------------------|----------|------------|---------|---------|-------|
| 30 MB | 5s | 5s | 30s | 5s | ~45s |
| 300 MB | 1 min | 30s | 3 min | 10s | ~5 min |
| 3 GB | 8 min | 5 min | 25 min | 30s | ~40 min |
| 30 GB | 1.5 hr | 45 min | 4 hr | 2 min | ~6.5 hr |

**Factors**:
- Network download speed
- CPU for decompression
- Disk I/O for restore
- Index rebuild during restore
- Verification query complexity

### Resource Utilization

**Backup Service**:
```
CPU:    10-30% during backup, <1% idle
Memory: 64-256 MB (depends on pg_dump buffer)
Disk:   2× backup size (temporary storage)
Network: 1-10 Mbps upload (depends on file size)
```

**Verify Service**:
```
CPU:    20-50% during restore, <1% idle
Memory: 128-512 MB (depends on database size)
Disk:   4× backup size (compressed + decompressed + temp DB)
Network: 1-10 Mbps download
```

## Scalability & Limitations

### Scalability

**Horizontal Scaling**:
- ❌ Not applicable (stateless services, one per database)
- ✅ Deploy multiple instances for multiple databases

**Vertical Scaling**:
- ✅ Larger databases need more memory and CPU
- ✅ Faster backups with more CPU cores (parallel pg_dump)
- ✅ Faster uploads with better network

**Storage Scaling**:
- ✅ Unlimited (S3-compatible storage scales infinitely)
- ⚠️ Cost increases linearly with retention period

### Limitations

| Limitation | Value | Workaround |
|------------|-------|------------|
| Max database size | ~500 GB practical | Use parallel pg_dump, longer intervals |
| Max backup size | S3 provider limit (usually 5 TB) | Split into multiple databases |
| Min backup interval | ~60 seconds | Not recommended, use replication instead |
| Max retention | No hard limit | Cost increases with retention |
| Concurrent backups | 1 per service instance | Deploy multiple instances |
| PostgreSQL versions | 12-16 tested | May work with older/newer versions |
| Network bandwidth | Depends on provider | Choose S3 provider geographically close |
| Disk space | 4× largest backup | Monitor and alert on disk usage |

### Known Constraints

1. **No Point-in-Time Recovery**: Only full backups at intervals
2. **No Incremental Backups**: Each backup is full database dump
3. **No Parallel Restore**: psql is single-threaded
4. **No Cross-Version Support**: Backup from PG 16 may not restore to PG 12
5. **No Automatic Failover**: Manual intervention required for disasters
6. **No Built-in Monitoring**: Use external monitoring tools
7. **No GUI**: CLI and logs only

### Future Enhancements

See [SPEC.md](../SPEC.md) for planned features in v1.1 and beyond.

---

**Document Version**: 1.0.0
**Implementation Version**: 1.0.0
**Status**: ✅ Complete and Accurate
**Last Updated**: 2024-02-07
**Next Review**: 2024-05-07
