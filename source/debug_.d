module debug_;
import nulib.io.stream : Stream;
import nulib.io.stream.file : FileStream;
import numem;
import inp.format;
import std.conv;
import std.base64;
import std.stdio : File;

/**
	Utility function that reads a model out into a data node.
*/
void readModelData(string file, ref DataNode node) {
	return readModelData(nogc_new!FileStream(file, "r+b"), node);
}

/**
	Utility function that reads a model out into a data node.
*/
void readModelData(Stream stream, ref DataNode node) {
	auto result = stream.readINP();
	if (result.isOK)
		node = result.getOr(DataNode.init);
}

struct FileSink {
	File file;

	void write(string text) {
		file.write(text);
	}
}




void dumpDataNodeJSON(SinkT)(ref SinkT sink, ref DataNode node)
if (is(typeof(() => sink.write("a")))) {
	final switch(node.type) with(DataNodeType) {
		case undefined:
			sink.write("null");
			break;
		case boolean_:
			sink.write(node.tryCoerce!bool ? "true" : "false");
			break;
		case int_:
			sink.write(node.tryCoerce!(long).text);
			break;
		case uint_:
			sink.write(node.tryCoerce!(ulong).text);
			break;
		case float_:
			sink.write(node.tryCoerce!(float).text);
			break;
		case string_:
			sink.write("\"");
			sink.write(node.text);
			sink.write("\"");
			break;
		case array_:
			sink.write("[");
			foreach(i, ref child; node.array) {
				sink.dumpDataNodeJSON(child);
				
				if (i+1 < node.length)
					sink.write(",");
			}
			sink.write("]");
			break;
		case object_:
			sink.write("{");
			size_t i = 0;
			foreach(key, ref child; node.object) {
				sink.write("\"");
				sink.write(key);
				sink.write("\":");
				sink.dumpDataNodeJSON(child);
				
				if (i+1 < node.length)
					sink.write(",");
				i++;
			}
			sink.write("}");
			break;
		case blob_:
			sink.write("\"");
			sink.write(Base64.encode(node.blob));
			sink.write("\"");
			break;
	}
}