/* Table definitions for SPSID data store */


CREATE TABLE SPSID_OBJECTS
(
  OBJECT_ID             VARCHAR(32) NOT NULL PRIMARY KEY,
  OBJECT_DELETED        INTEGER NOT NULL DEFAULT 0,
  OBJECT_CLASS          VARCHAR(60) NOT NULL,
  OBJECT_CONTAINER      VARCHAR(32) NOT NULL,
  
  CONSTRAINT SPSID_OBJECTS_UC01 UNIQUE (OBJECT_ID)
) CHARACTER SET ascii;

CREATE INDEX SPSID_OBJECTS_I01
  ON SPSID_OBJECTS(OBJECT_CONTAINER, OBJECT_CLASS, OBJECT_DELETED);

CREATE INDEX SPSID_OBJECTS_I02
  ON SPSID_OBJECTS(OBJECT_CLASS, OBJECT_DELETED);


CREATE TABLE SPSID_OBJECT_ATTR
(
  OBJECT_ID             VARCHAR(32) NOT NULL,
  ATTR_NAME             VARCHAR(60) NOT NULL,
  ATTR_VALUE            VARCHAR(256) CHARACTER SET utf8 NOT NULL,
  ATTR_LOWER            VARCHAR(256) NOT NULL,

  CONSTRAINT SPSID_OBJECTS_UC01 UNIQUE (OBJECT_ID, ATTR_NAME)
) CHARACTER SET ascii;

CREATE INDEX SPSID_OBJECT_ATTR_I01
  ON SPSID_OBJECT_ATTR(ATTR_NAME, ATTR_VALUE);

CREATE INDEX SPSID_OBJECT_ATTR_I02
  ON SPSID_OBJECT_ATTR(ATTR_NAME, ATTR_LOWER);

  
CREATE TABLE SPSID_OBJECT_LOG
(
  OBJECT_ID             VARCHAR(32) NOT NULL,
  LOG_TS                NUMERIC(16) NOT NULL,
  APPLICATION           VARCHAR(32) NOT NULL DEFAULT 'SPSID',
  USER_ID               VARCHAR(256) NOT NULL,
  MESSAGE               VARCHAR(2048) CHARACTER SET utf8 NOT NULL
) CHARACTER SET ascii;

CREATE INDEX SPSID_OBJECT_LOG_I01
  ON SPSID_OBJECT_LOG(OBJECT_ID, LOG_TS);



 /* DBIx::Sequence backend, the platform-independent inplementation
    of sequences */
 CREATE TABLE dbix_sequence_state
 (
   dataset varchar(50) NOT NULL, 
   state_id INTEGER NOT NULL, 
   CONSTRAINT pk_dbix_sequence PRIMARY KEY (dataset, state_id)
 );

 CREATE TABLE dbix_sequence_release
 (
   dataset varchar(50) NOT NULL,    
   released_id INTEGER NOT NULL, 
   CONSTRAINT pk_dbi_release PRIMARY KEY (dataset, released_id)
 );
