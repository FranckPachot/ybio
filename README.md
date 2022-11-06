# ybio
ybio is a row-access micro-benchmarking for PostgreSQL or YugabyteDB based on https://github.com/therealkevinc/pgio, following Kevin Closson SLOB method (https://kevinclosson.net/slob/). The main difference is that PGIO (for PostgreSQL, and SLOB for Oracle) are designed for block-based heap tables whereas this ybio alternative is designed for YugabyteDB which stores rows in DocDB which is a LSM Tree document store. What we measure is a number of rows per second (RIOPS - Row IO per second).

The idea is to read rows at random within a table in order to get an homogeneous workload, and predictable measure, to test a platform (compare compute shapes, CPU, processor architecture, block storage, memory, IO path...). The parameters (number of rows, percentage of updates,... can be set to focus on the desired workload (measure CPU and memory with a scale that fits in cache, disk IOPS with larger scale, concurrent access when touching the same table from multiple sessions,...)

The original PGIO can be used on YugabyteDB with a few tricks (see https://dev.to/yugabyte/slob-on-yugabytedb-1a32) but this ybio is adapted to be run both on PostgreSQL and any PostgreSQL compatible database (like AWS Aurora or YugabyteDB https://www.yugabyte.com/), whatever the storage engine.

# understand

It is important to understand the access path. On a distributed database, the table created is hash-sharded on a generated UUID (this is the default on YugabyteDB when we do not define a primary key). Rows are scattered without specific order (because of this hash and because they are inserted ordered on a random value). The index on the "mykey" column is created as range-sharded. The purpose is to range scan the index so that most of the work is reading scattered rows from the table.

The access path with the default index_only=>false is:
```
yugabyte=# explain (analyze, verbose) select count(*),sum(scratch) from bench0001 where mykey between 1 and 10;
                                                                 QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------------------------
 Aggregate  (cost=5.30..5.31 rows=1 width=40) (actual time=2.214..2.214 rows=1 loops=1)
   Output: count(*), sum(scratch)
   ->  Index Scan using bench0001_asc_mykey on public.bench0001  (cost=0.00..5.25 rows=10 width=8) (actual time=2.056..2.056 rows=0 loops=1)
         Output: mykey, scratch, filler
         Index Cond: ((bench0001.mykey >= 1) AND (bench0001.mykey <= 10))
 Planning Time: 0.053 ms
 Execution Time: 2.267 ms
```

When specifying index_only=>true (in case you want to measure range scans rather than random reads):
```
yugabyte=# explain (analyze, verbose) select count(*),sum(mykey) from bench0001 where mykey between 1 and 10;
                                                                    QUERY PLAN
--------------------------------------------------------------------------------------------------------------------------------------------------
 Aggregate  (cost=5.20..5.21 rows=1 width=40) (actual time=2.697..2.697 rows=1 loops=1)
   Output: count(*), sum(mykey)
   ->  Index Only Scan using bench0001_asc_mykey on public.bench0001  (cost=0.00..5.15 rows=10 width=8) (actual time=2.693..2.693 rows=0 loops=1)
         Output: mykey
         Index Cond: ((bench0001.mykey >= 1) AND (bench0001.mykey <= 10))
         Heap Fetches: 0
 Planning Time: 0.057 ms
 Execution Time: 2.740 ms
```

Finally, when defining a pct_update>0 the following update will be run instead of the select with the desired frequency:
```
yugabyte=# explain (analyze) with u as (update bench0001 set scratch=scratch+1 where mykey between 1 and 10 returning 1,scratch) select count(*),max(scratch) from u;
                                                                   QUERY PLAN
------------------------------------------------------------------------------------------------------------------------------------------------
 Aggregate  (cost=5.53..5.54 rows=1 width=16) (actual time=1.203..1.204 rows=1 loops=1)
   CTE u
     ->  Update on bench0001  (cost=0.00..5.28 rows=10 width=104) (actual time=1.200..1.200 rows=0 loops=1)
           ->  Index Scan using bench0001_asc_mykey on bench0001  (cost=0.00..5.28 rows=10 width=104) (actual time=1.199..1.199 rows=0 loops=1)
                 Index Cond: ((mykey >= 1) AND (mykey <= 10))
   ->  CTE Scan on u  (cost=0.00..0.20 rows=10 width=8) (actual time=1.201..1.201 rows=0 loops=1)
 Planning Time: 0.756 ms
 Execution Time: 2.670 ms
```

It can be interesting to read this post I've written when running PGIO on YBDB: https://dev.to/yugabyte/slob-on-yugabytedb-1a32

# install

This is quite easy, just run the ybio.sql that creates the setup() and runit() procedure as weel as the benchruns table that will store the results of each runs.

# setup

call the setup() procedure

example:
```
call setup(tab_prefix=>'bench',tab_num=>1,tab_rows=>1e6::int,batch_size=>10000);
```
will create a bench0001 table with 1 million rows, in 100 batches of 10000 rows (this si important for YugabyteDB that is optimized for OLTP with short transactions).
Additional parameters:
 - tab_tablets: defines the number of YugabyteDB tablets for the table (SPLIT INTO clause). The default 0 will use the default from the YB server
 - ind_tablets: defines the number of YugabyteDB tablets for the index (SPLIT AT clause). The default 0 will use the default (one tablet).
 - filler: is the size of an additional column in the rows that can be used to create larger rows
 - recreate: by default at true which will drop the existing tables before re-creating them
 - index_as_pk: by default at false so we have no primary key (which means in YugabyteDB a UUID is created for the PK) so that we have rows scattered. For database with heap tables (PostgreSQL) better to define "mykey" as the primary key as it doesn't change the physical organisation
 - orderby: the default is 'scratch' which is the random column so that inserts are scattered. With null, it will be ordered as generated (no order by). `yb_hash_code(mykey)`

You can create many tables (with a different tab_num) if you want to run multiple sessions concurrently that doesn't touch the same table.

Example of output:
```
yb=> call setup(tab_prefix=>'bench',tab_num=>1,tab_rows=>1e6::int,batch_size=>100000);
NOTICE:  Inserting 1000000 rows in 10 batches of 100000
NOTICE:  Table bench0001 Progress:   10.00 % (100000 rows)
NOTICE:  Table bench0001 Progress:   20.00 % (200000 rows)
NOTICE:  Table bench0001 Progress:   30.00 % (300000 rows)
NOTICE:  Table bench0001 Progress:   40.00 % (400000 rows)
NOTICE:  Table bench0001 Progress:   50.00 % (500000 rows)
NOTICE:  Table bench0001 Progress:   60.00 % (600000 rows)
NOTICE:  Table bench0001 Progress:   70.00 % (700000 rows)
NOTICE:  Table bench0001 Progress:   80.00 % (800000 rows)
NOTICE:  Table bench0001 Progress:   90.00 % (900000 rows)
NOTICE:  Table bench0001 Progress:  100.00 % (1000000 rows)
CALL
```

# run it

call the runit() procedure

example:
```
call runit(tab_prefix=>'bench',tab_num=>1,tab_rows=>1e6::int,run_duration=>interval '1 minutes',pct_update=>10,batch_size=>1e4::int);
```
will run a session for one minute reading a set of 10000 rows within the first 1 million in the bench0001 table (be sure to have inserted enough with setup) and updating 10% of those rows. Note that running with a tab_num lower than the rows inserted by setup means that the number of rows selected by the random range will be lower than the batch size.
Additional parameters:
 - prepared defaults to true in order to use prepared statements
 - index_only defaults to false in order to read from the table (we do a range scan on the index but read rows scattered within the table)
 - initial_count defaults to false. Set it to true in order to start with counting the rows in the table

Example of output:
```
yb=> deallocate all;
DEALLOCATE ALL

yb=> call runit(tab_prefix=>'bench',tab_num=>1,tab_rows=>1e6::int,run_duration=>interval '10 seconds',pct_update=>42,batch_size=>1e5::int);
NOTICE:   1313560 rows/s on bench0001, job:      4 batch#:     1, total:       100000 rows read,     .0 % updated, last: 100000 rows between  556938 and 456939
NOTICE:    161947 rows/s on bench0001, job:      4 batch#:     2, total:       200000 rows read,   50.0 % updated, last: 100000 rows between  817053 and 717054
NOTICE:    230730 rows/s on bench0001, job:      4 batch#:     3, total:       300000 rows read,   33.3 % updated, last: 100000 rows between  105852 and 5853
NOTICE:    167653 rows/s on bench0001, job:      4 batch#:     4, total:       400000 rows read,   50.0 % updated, last: 100000 rows between  536551 and 436552
NOTICE:    203375 rows/s on bench0001, job:      4 batch#:     5, total:       500000 rows read,   40.0 % updated, last: 100000 rows between  741972 and 641973
NOTICE:    163239 rows/s on bench0001, job:      4 batch#:     6, total:       600000 rows read,   50.0 % updated, last: 100000 rows between  369749 and 269750
NOTICE:    186928 rows/s on bench0001, job:      4 batch#:     7, total:       700000 rows read,   42.9 % updated, last: 100000 rows between  723871 and 623872
NOTICE:    209561 rows/s on bench0001, job:      4 batch#:     8, total:       800000 rows read,   37.5 % updated, last: 100000 rows between  429001 and 329002
NOTICE:    169438 rows/s on bench0001, job:      4 batch#:     9, total:       900000 rows read,   44.4 % updated, last: 100000 rows between  675752 and 575753
NOTICE:    184641 rows/s on bench0001, job:      4 batch#:    10, total:      1000000 rows read,   40.0 % updated, last: 100000 rows between  830203 and 730204
NOTICE:    148161 rows/s on bench0001, job:      4 batch#:    11, total:      1100000 rows read,   45.5 % updated, last: 100000 rows between  127679 and 27680
NOTICE:    159453 rows/s on bench0001, job:      4 batch#:    12, total:      1200000 rows read,   41.7 % updated, last: 100000 rows between  692078 and 592079
NOTICE:    170531 rows/s on bench0001, job:      4 batch#:    13, total:      1300000 rows read,   38.5 % updated, last: 100000 rows between  199321 and 99322
NOTICE:    150396 rows/s on bench0001, job:      4 batch#:    14, total:      1400000 rows read,   42.9 % updated, last: 100000 rows between  545806 and 445807
NOTICE:    159588 rows/s on bench0001, job:      4 batch#:    15, total:      1500000 rows read,   40.0 % updated, last: 100000 rows between  201965 and 101966
CALL
```

# read results
The run displays a notice for each batch of rows but the summary is stored in the benchruns table:
```
opc=> select end_time-start_time duration,round(num_rows/extract(epoch from end_time-start_time)) riops
      ,round(100*max_scratch::float/table_scratch) as pct_scratch
      , case when num_rows > table_rows then lpad(to_char(num_rows::float/table_rows,'xfmB9990D9'),6)
        else lpad(to_char(100*num_rows/table_rows,'fmB999 %'),6) end coverage
      ,* from benchruns order by job_id desc nulls last limit 10;
      
    duration     | riops | pct_scratch | coverage | job_id |         start_time         |          end_time          | num_batches | num_rows | pct_update | max_scratch | prepared | index_only | tab_rows | batch_size | table_name | table_rows | table_scratch
-----------------+-------+-------------+----------+--------+----------------------------+----------------------------+-------------+----------+------------+-------------+----------+------------+----------+------------+------------+------------+---------------
                 |       |             |          |   4701 | 2021-07-30 03:50:20.00427  |                            |             |          |         10 |             | t        | f          |  1000000 |        100 | bench0001  |            |
 00:10:00.010691 | 14300 |             |          |   4601 | 2021-07-30 03:40:19.521098 | 2021-07-30 03:50:19.531789 |      115571 |  8579921 |         10 |    10000008 | t        | f          |  1000000 |         75 | bench0001  |            |
 00:10:00.008916 | 13101 |             |          |   4501 | 2021-07-30 03:30:18.967942 | 2021-07-30 03:40:18.976858 |      158772 |  7860486 |         10 |    10000007 | t        | f          |  1000000 |         50 | bench0001  |            |
 00:10:00.018242 |  9493 |             |          |   4401 | 2021-07-30 03:20:18.242007 | 2021-07-30 03:30:18.260249 |      230157 |  5695852 |         10 |    10000005 | t        | f          |  1000000 |         25 | bench0001  |            |
 00:10:00.006399 |  4962 |             |          |   4301 | 2021-07-30 03:10:17.505551 | 2021-07-30 03:20:17.51195  |      300647 |  2976935 |         10 |    10000005 | t        | f          |  1000000 |         10 | bench0001  |            |
 00:10:00.005778 |   563 |             |          |   4201 | 2021-07-30 03:00:16.952416 | 2021-07-30 03:10:16.958194 |      341014 |   337613 |         10 |    10000003 | t        | f          |  1000000 |          1 | bench0001  |            |
 00:10:17.721976 | 32053 |             |          |   4101 | 2021-07-30 02:49:58.794436 | 2021-07-30 03:00:16.516412 |          20 | 19799980 |          5 |    10000005 | t        | f          |  1000000 |    1000000 | bench0001  |            |
 00:10:08.574929 | 34499 |             |          |   4001 | 2021-07-30 02:39:49.808119 | 2021-07-30 02:49:58.383048 |          28 | 20995158 |          5 |    10000004 | t        | f          |  1000000 |     750000 | bench0001  |            |
 00:10:01.014065 | 34109 |             |          |   3901 | 2021-07-30 02:29:48.396392 | 2021-07-30 02:39:49.410457 |          41 | 20500000 |          5 |    10000003 | t        | f          |  1000000 |     500000 | bench0001  |            |
 00:10:03.313616 | 30222 |             |          |   3801 | 2021-07-30 02:19:44.666775 | 2021-07-30 02:29:47.980391 |          73 | 18233325 |          5 |    10000001 | t        | f          |  1000000 |     250000 | bench0001  |            |
```
The RIOPS here is the rows per second that were read or updated.

Here is an example where I graph'd it with [Arctype](https://blog.yugabyte.com/connecting-to-yugabytedb-with-arctype-a-collaborative-sql-client/) to see the impact of the batch_size parameter on the read rate - minimizing the calls between YSQL and DocDB by reading 10's thousand of rows can reach 75000 rows per second from a single session here (and this is how we can scale thanks to SQL and PL/pgSQL): ![BatchSizeExample](https://user-images.githubusercontent.com/33070466/127613823-985956d2-5540-4d61-9486-a146c2841aae.png)

