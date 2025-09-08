/**
    OpenGL Abstractions to make the code more readable.
*/
module gl;
import bindbc.opengl;
import inmath.linalg;
import inochi2d;

public import nulib;
public import numem;

class GLTexture : NuObject {
private:
@nogc:
    GLenum color;
    uint width;
    uint height;

public:

    /**
        OpenGL ID
    */
    GLuint id;

    // Destructor
    ~this() {
        glDeleteTextures(1, &id);
    }

    /**
        Creates a new texture.
    */
    this(GLenum color, uint width, uint height) {
        this.color = color;
        this.width = width;
        this.height = height;
        glGenTextures(1, &id);
        glBindTexture(GL_TEXTURE_2D, id);
        glTexImage2D(GL_TEXTURE_2D, 0, color, width, height, 0, color, GL_UNSIGNED_BYTE, null);
        glTextureParameteri(id, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTextureParameteri(id, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTextureParameteri(id, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
        glTextureParameteri(id, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);
    }

    /**
        Creates a new texture with data.
    */
    this(GLenum color, uint width, uint height, void* data) {
        glGenTextures(1, &id);
        glBindTexture(GL_TEXTURE_2D, id);

        glTexImage2D(GL_TEXTURE_2D, 0, color, width, height, 0, color, GL_UNSIGNED_BYTE, data);
        glTextureParameteri(id, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTextureParameteri(id, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTextureParameteri(id, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
        glTextureParameteri(id, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);
    }

    /**
        Resizes the texture.
    */
	void resize(uint width, uint height) {
        if (this.width == width && this.height == height)
            return;

        this.width = width;
        this.height = height;
        
        glBindTexture(GL_TEXTURE_2D, id);
        glTexImage2D(GL_TEXTURE_2D, 0, color, width, height, 0, color, GL_UNSIGNED_BYTE, null);
	}

    /**
        Binds texture to the given unit.
    */
    void bind(uint unit) {
        glBindTextureUnit(unit, id);
    } 
}

class GLFramebuffer : NuObject {
private:
@nogc:
    uint width;
    uint height;

    void reattachAll() {
        foreach(i, texture; textures)
            if (texture)
                glNamedFramebufferTexture(id, cast(GLenum)(GL_COLOR_ATTACHMENT0+i), texture.id, 0);
    }

public:

    /**
        Textures attached to the framebuffer.
    */
	weak_vector!GLTexture textures;

    /**
        OpenGL ID
    */
    GLuint id;

    /// destructor
    ~this() {
        glDeleteFramebuffers(1, &id);
    }

    /**
        Creates a new framebuffer.
    */
	this(uint width, uint height, string label) {
        this.width = width;
        this.height = height;

		glGenFramebuffers(1, &id);
		glObjectLabel(GL_FRAMEBUFFER, id, cast(int)label.length, label.ptr);
	}

    /**
        Resizes the framebuffer.
    */
	void resize(uint width, uint height) {
        if (this.width == width && this.height == height)
            return;

        this.width = width;
        this.height = height;
		foreach(i, texture; textures) {
            if (texture)
                texture.resize(width, height);
		}
	}

    /**
        Attaches a texture to the framebuffer.
    */
    void attach(GLTexture texture) {
        textures ~= texture;
    }

    /**
        Binds as target.
    */
    void bindAsTarget(uint offset = 0) {
        foreach(i, texture; textures) {
            if (texture)
                glBindTextureUnit(cast(uint)i+offset, texture.id);
        }
    }

    /**
        Uses the framebuffer.
    */
    void use() {
        glBindFramebuffer(GL_FRAMEBUFFER, id);
        this.reattachAll();
    }

    /**
        Blits this framebuffer to the given target.
    */
    void blitTo(GLFramebuffer fb) {
        if (fb) {
            glBindFramebuffer(GL_READ_FRAMEBUFFER, id);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fb.id);
            glBlitFramebuffer(0, 0, width, height, 0, 0, fb.width, fb.height, GL_COLOR_BUFFER_BIT, GL_LINEAR);
            return;
        }

        glBindFramebuffer(GL_READ_FRAMEBUFFER, id);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
        glBlitFramebuffer(0, 0, width, height, 0, 0, width, height, GL_COLOR_BUFFER_BIT, GL_LINEAR);
    }
}

class GLShader : NuObject {
public:
@nogc:

    /**
        OpenGL ID
    */
    GLuint id;

    // Destructor
    ~this() {
        glDeleteProgram(id);
    }

	/**
		Constructs a shader.
	*/
	this(string vertex, string fragment, string label) {
		const(char)* vSrc = vertex.ptr;
		const(char)* fSrc = fragment.ptr;

		GLuint vshader = glCreateShader(GL_VERTEX_SHADER);
		glShaderSource(vshader, 1, &vSrc, null);
		glCompileShader(vshader);

		GLuint fshader = glCreateShader(GL_FRAGMENT_SHADER);
		glShaderSource(fshader, 1, &fSrc, null);
		glCompileShader(fshader);
		
		GLuint program = glCreateProgram();
		glAttachShader(program, vshader);
		glAttachShader(program, fshader);
		glLinkProgram(program);
		glUseProgram(program);

		glObjectLabel(GL_PROGRAM, program, cast(int)label.length, label.ptr);

		glDeleteShader(vshader);
		glDeleteShader(fshader);

		id = program;
	}

    /**
        Gets the location of a uniform.
    */
    GLuint getUniformLocation(string name) {
        return glGetUniformLocation(id, name.ptr);
    }

    /**
        Sets the current active matrix.
    */
    void setUniform(uint location, int value) {
        glUniform1i(location, value);
    }

    /**
        Sets the current active matrix.
    */
    void setUniform(uint location, float value) {
        glUniform1f(location, value);
    }

    /**
        Sets the current active matrix.
    */
    void setUniform(uint location, mat4 value) {
        glUniformMatrix4fv(location, 1, GL_TRUE, value.ptr);
    }

    /**
        Use this shader.
    */
    void use() {
        glUseProgram(id);
    }
}

void inSetBlendModeLegacy(BlendMode blendingMode) {
	switch(blendingMode) {
		
		// If the advanced blending extension is not supported, force to Normal blending
		default:
			glBlendEquation(GL_FUNC_ADD);
			glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA); break;

		case BlendMode.normal: 
			glBlendEquation(GL_FUNC_ADD);
			glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA); break;

		case BlendMode.multiply: 
			glBlendEquation(GL_FUNC_ADD);
			glBlendFunc(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA); break;

		case BlendMode.screen:
			glBlendEquation(GL_FUNC_ADD);
			glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_COLOR); break;

		case BlendMode.lighten:
			glBlendEquation(GL_MAX);
			glBlendFunc(GL_ONE, GL_ONE); break;

		case BlendMode.colorDodge:
			glBlendEquation(GL_FUNC_ADD);
			glBlendFunc(GL_DST_COLOR, GL_ONE); break;

		case BlendMode.linearDodge:
			glBlendEquation(GL_FUNC_ADD);
			glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_COLOR, GL_ONE, GL_ONE_MINUS_SRC_ALPHA); break;
			
		case BlendMode.addGlow:
			glBlendEquation(GL_FUNC_ADD);
			glBlendFuncSeparate(GL_ONE, GL_ONE, GL_ONE, GL_ONE_MINUS_SRC_ALPHA); break;

		case BlendMode.subtract:
			glBlendEquationSeparate(GL_FUNC_REVERSE_SUBTRACT, GL_FUNC_ADD);
			glBlendFunc(GL_ONE_MINUS_DST_COLOR, GL_ONE); break;

		case BlendMode.exclusion:
			glBlendEquation(GL_FUNC_ADD);
			glBlendFuncSeparate(GL_ONE_MINUS_DST_COLOR, GL_ONE_MINUS_SRC_COLOR, GL_ONE, GL_ONE); break;

		case BlendMode.inverse:
			glBlendEquation(GL_FUNC_ADD);
			glBlendFunc(GL_ONE_MINUS_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA); break;
		
		case BlendMode.destinationIn:
			glBlendEquation(GL_FUNC_ADD);
			glBlendFunc(GL_ZERO, GL_SRC_ALPHA); break;

		case BlendMode.sourceIn:
			glBlendEquation(GL_FUNC_ADD);
			glBlendFunc(GL_DST_ALPHA, GL_ONE_MINUS_SRC_ALPHA); break;

		case BlendMode.sourceOut:
			glBlendEquation(GL_FUNC_ADD);
			glBlendFunc(GL_ZERO, GL_ONE_MINUS_SRC_ALPHA); break;
	}
}