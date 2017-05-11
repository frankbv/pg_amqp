-- You must also still run "ALTER EXTENSION pg_ampq UPDATE' to update the extension version number in the database.

CREATE TEMP TABLE amqp_preserve_privs_temp (statement text);

INSERT INTO amqp_preserve_privs_temp
SELECT 'GRANT EXECUTE ON FUNCTION @extschema@.autonomous_publish(integer, varchar, varchar, varchar, integer, varchar, varchar, varchar, varchar[]) TO '||array_to_string(array_agg(grantee::text), ',')||';'
FROM information_schema.routine_privileges
WHERE routine_schema = '@extschema@'
AND routine_name = 'autonomous_publish';

INSERT INTO amqp_preserve_privs_temp
SELECT 'GRANT EXECUTE ON FUNCTION @extschema@.publish(integer, varchar, varchar, varchar, integer, varchar, varchar, varchar, varchar[]) TO '||array_to_string(array_agg(grantee::text), ',')||';'
FROM information_schema.routine_privileges
WHERE routine_schema = '@extschema@'
AND routine_name = 'publish';

DROP FUNCTION @extschema@.autonomous_publish(integer, varchar, varchar, varchar, integer, varchar, varchar, varchar);
DROP FUNCTION @extschema@.publish(integer, varchar, varchar, varchar, integer, varchar, varchar, varchar);

CREATE FUNCTION @extschema@.autonomous_publish(
    broker_id integer
    , exchange varchar
    , routing_key varchar
    , message varchar
    , delivery_mode integer default null
    , content_type varchar default null
    , reply_to varchar default null
    , correlation_id varchar default null
    , headers varchar[] default null
)

RETURNS boolean AS 'pg_amqp.so', 'pg_amqp_autonomous_publish'
LANGUAGE C IMMUTABLE;

COMMENT ON FUNCTION @extschema@.autonomous_publish(integer, varchar, varchar, varchar, integer, varchar, varchar, varchar, varchar[]) IS
'Works as amqp.publish does, but the message is published immediately irrespective of the
current transaction state.  PostgreSQL commit and rollback at a later point will have no
effect on this message being sent to AMQP.';


CREATE FUNCTION @extschema@.publish(
    broker_id integer
    , exchange varchar
    , routing_key varchar
    , message varchar
    , delivery_mode integer default null
    , content_type varchar default null
    , reply_to varchar default null
    , correlation_id varchar default null
    , headers varchar[] default null
)
RETURNS boolean AS 'pg_amqp.so', 'pg_amqp_publish'
LANGUAGE C IMMUTABLE;

COMMENT ON FUNCTION @extschema@.publish(integer, varchar, varchar, varchar, integer, varchar, varchar, varchar, varchar[]) IS
'Publishes a message (broker_id, exchange, routing_key, message).
The message will only be published if the containing PostgreSQL transaction successfully commits.
Under certain circumstances, the AMQP commit might fail.  In this case, a WARNING is emitted.
The last five parameters are optional and set the following message properties:
delivery_mode (either 1 or 2), content_type, reply_to, correlation_id and headers.

Publish returns a boolean indicating if the publish command was successful.  Note that as
AMQP publish is asynchronous, you may find out later it was unsuccessful.';

-- Restore dropped object privileges
DO $$
DECLARE
v_row   record;
BEGIN
    FOR v_row IN SELECT statement FROM amqp_preserve_privs_temp LOOP
        IF v_row.statement IS NOT NULL THEN
            EXECUTE v_row.statement;
        END IF;
    END LOOP;
END
$$;

DROP TABLE IF EXISTS amqp_preserve_privs_temp;
