DELETE
  SPSID_OBJECTS, SPSID_OBJECT_ATTR, SPSID_OBJECT_LOG
FROM
  SPSID_OBJECTS, SPSID_OBJECT_ATTR, SPSID_OBJECT_LOG
WHERE
  SPSID_OBJECTS.OBJECT_DELETED=1 AND
  SPSID_OBJECT_ATTR.OBJECT_ID=SPSID_OBJECTS.OBJECT_ID AND
  SPSID_OBJECT_LOG.OBJECT_ID=SPSID_OBJECTS.OBJECT_ID;

COMMIT;
