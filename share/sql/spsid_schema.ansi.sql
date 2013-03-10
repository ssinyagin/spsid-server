/* Table definitions for SPSID data store */


CREATE TABLE SPSID_OBJECTS
(
  OBJECT_ID             VARCHAR(32) NOT NULL PRIMARY KEY,
  OBJECT_DELETED        INTEGER NOT NULL DEFAULT 0,
  OBJECT_CLASS          VARCHAR(60) NOT NULL,
  OBJECT_CONTAINER      VARCHAR(32) NOT NULL,
  
  CONSTRAINT SPSID_OBJECTS_UC01 UNIQUE (OBJECT_ID)
);

CREATE INDEX SPSID_OBJECTS_I01
  ON SPSID_OBJECTS(OBJECT_CONTAINER, OBJECT_CLASS, OBJECT_DELETED);

CREATE INDEX SPSID_OBJECTS_I02
  ON SPSID_OBJECTS(OBJECT_CLASS, OBJECT_DELETED);


CREATE TABLE SPSID_OBJECT_ATTR
(
  OBJECT_ID             VARCHAR(32) NOT NULL,
  ATTR_NAME             VARCHAR(60) NOT NULL,
  ATTR_VALUE            VARCHAR(256) NOT NULL,
  ATTR_LOWER            VARCHAR(256) NOT NULL,

  CONSTRAINT SPSID_OBJECTS_UC01 UNIQUE (OBJECT_ID, ATTR_NAME, ATTR_VALUE)
);

CREATE INDEX SPSID_OBJECT_ATTR_I01
  ON SPSID_OBJECT_ATTR(OBJECT_ID, ATTR_NAME);

CREATE INDEX SPSID_OBJECT_ATTR_I02
  ON SPSID_OBJECT_ATTR(ATTR_NAME, ATTR_VALUE);

CREATE INDEX SPSID_OBJECT_ATTR_I03
  ON SPSID_OBJECT_ATTR(ATTR_NAME, ATTR_LOWER);

  
CREATE TABLE SPSID_OBJECT_LOG
(
  OBJECT_ID             VARCHAR(32) NOT NULL,
  LOG_TS                INTEGER(16) NOT NULL,
  USER_ID               VARCHAR(32) NOT NULL,
  MESSAGE               VARCHAR(2048) NOT NULL
);

CREATE INDEX SPSID_OBJECT_LOG_I01
  ON SPSID_OBJECT_LOG(OBJECT_ID, LOG_TS);



