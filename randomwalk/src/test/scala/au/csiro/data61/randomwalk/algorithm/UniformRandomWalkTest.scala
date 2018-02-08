package au.csiro.data61.randomwalk.algorithm

import au.csiro.data61.randomwalk.common.CommandParser.{RrType, TaskName}
import au.csiro.data61.randomwalk.common.Params
import org.apache.spark.{SparkConf, SparkContext}
import org.scalatest.BeforeAndAfter

import scala.collection.mutable


class UniformRandomWalkTest extends org.scalatest.FunSuite with BeforeAndAfter {

  private val karate = "./src/test/resources/karate.txt"
  private val testGraph = "./src/test/resources/testgraph.txt"
  private val master = "local[*]" // Note that you need to verify unit tests in a multi-core
  // computer.
  private val appName = "rw-unit-test"
  private var sc: SparkContext = _

  before {
    // Note that the Unit Test may throw "java.lang.AssertionError: assertion failed: Expected
    // hostname"
    // If this test is running in MacOS and without Internet connection.
    // https://issues.apache.org/jira/browse/SPARK-19394
    val conf = new SparkConf().setMaster(master).setAppName(appName)
    sc = SparkContext.getOrCreate(conf)
  }

  after {
    if (sc != null) {
      sc.stop()
    }
    GraphMap.reset
  }

  test("load graph as undirected") {
    val config = Params(input = karate, directed = false)
    val rw = UniformRandomWalk(sc, config)
    val paths = rw.loadGraph() // loadGraph(int)
    assert(rw.nEdges == 156)
    assert(rw.nVertices == 34)
    assert(paths.count() == 34)
    val vAcc = sc.longAccumulator("v")
    val eAcc = sc.longAccumulator("e")
    paths.coalesce(1).mapPartitions { iter =>
      vAcc.add(GraphMap.getNumVertices)
      eAcc.add(GraphMap.getNumEdges)
      iter
    }.first()
    assert(eAcc.sum == 156)
    assert(vAcc.sum == 34)
  }

  test("load graph as directed") {
    val config = Params(input = karate, directed = true)
    val rw = UniformRandomWalk(sc, config)
    val paths = rw.loadGraph()
    assert(rw.nEdges == 78)
    assert(rw.nVertices == 34)
    assert(paths.count() == 34)
    val vAcc = sc.longAccumulator("v")
    val eAcc = sc.longAccumulator("e")
    paths.coalesce(1).mapPartitions { iter =>
      vAcc.add(GraphMap.getNumVertices)
      eAcc.add(GraphMap.getNumEdges)
      iter
    }.first()
    assert(eAcc.sum == 78)
    assert(vAcc.sum == 34)
  }

  test("remove vertex") {
    val config = Params(input = karate, directed = false)
    val rw = UniformRandomWalk(sc, config)
    val target = 1
    val before = rw.readFromFile(config)
    rw.buildGraphMap(before)
    val neighbors = GraphMap.getNeighbors(target)
    val nDegrees = new mutable.HashMap[Int, Int]()
    for (n <- neighbors) {
      nDegrees.put(n._1, GraphMap.getNeighbors(n._1).length)
    }

    val after = rw.removeVertex(before, target)
    assert(after.count() == 33)
    assert(after.filter(_._1 == target).count() == 0)
    rw.buildGraphMap(after)
    for (n <- neighbors) {
      val newDegree = GraphMap.getNeighbors(n._1).length
      nDegrees.get(n._1) match {
        case Some(d) => assert(d - 1 == newDegree)
        case None => assert(false)
      }

    }
  }

  test("first order walk") {
    // Undirected graph
    val wLength = 50

    val config = Params(input = karate, directed = false, walkLength =
      wLength, rddPartitions = 8, numWalks = 1)
    val rw = UniformRandomWalk(sc, config)
    val rValue = 0.1f
    val nextFloatGen = () => rValue
    val graph = rw.loadGraph()
    val paths = rw.firstOrderWalk(graph, nextFloatGen)
    assert(paths.count() == rw.nVertices) // a path per vertex
    val rSampler = RandomSample(nextFloatGen)
    paths.collect().foreach { case (p: Array[Int]) =>
      val p2 = doFirstOrderRandomWalk(GraphMap, p(0), wLength, rSampler)
      assert(p sameElements p2)
    }
  }

  test("addAndRun m2") {
    // Undirected graph
    val wLength = 5

    val config = Params(input = karate, directed = false, walkLength =
      wLength, rddPartitions = 8, numWalks = 1, rrType = RrType.m2)
    val rw = UniformRandomWalk(sc, config)
    rw.addAndRun()
  }

  test("Query Nodes") {
    var config = Params(nodes = "1 2 3 4")

    val p1 = Array(1, 2, 1, 2, 1)
    val p2 = Array(2, 2, 2, 2, 1)
    val p3 = Array(3, 4, 2, 3)
    val p4 = Array(4)
    val expected = Array((1, (4, 2)), (2, (7, 3)), (3, (2, 1)), (4, (2, 2)))

    val paths = sc.parallelize(Array(p1, p2, p3, p4))
    var rw = UniformRandomWalk(sc, config)
    var counts = rw.queryPaths(paths)
    assert(counts sameElements expected)

    config = Params()
    rw = UniformRandomWalk(sc, config)
    counts = rw.queryPaths(paths)
    assert(counts sameElements expected)
  }

  test("Experiments") {
    val query = 1 to 34 toArray
    var config = Params(input = karate,
      output = "", directed = false, walkLength = 10,
      rddPartitions = 8, numWalks = 1, cmd = TaskName.firstorder, nodes = query.mkString(" "))
    var rw = UniformRandomWalk(sc, config)
    val g = rw.loadGraph()
    val paths = rw.firstOrderWalk(g)
    val counts1 = rw.queryPaths(paths)
    assert(counts1.length == 34)

    config = Params(input = karate, directed = false, walkLength = 10,
      rddPartitions = 8, numWalks = 1, cmd = TaskName.firstorder)

    rw = UniformRandomWalk(sc, config)
    val counts2 = rw.queryPaths(paths)
    assert(counts2.length == 34)

    assert(counts1.sortBy(_._1) sameElements counts2.sortBy(_._1))
  }

  private def doFirstOrderRandomWalk(gMap: GraphMap.type, src: Int,
                                     walkLength: Int, rSampler: RandomSample): Array[Int]
  = {
    var path = Array(src)

    for (_ <- 0 until walkLength) {

      val curr = path.last
      val currNeighbors = gMap.getNeighbors(curr)
      if (currNeighbors.length > 0) {
        path = path ++ Array(rSampler.sample(currNeighbors)._1)
      } else {
        return path
      }
    }

    path
  }

}
