CXX=g++

FLAGS=-pipe -fPIC #-g
CXXFLAGS=$(FLAGS) -Wall -Wextra
LDFLAGS=$(FLAGS)

#LDFLAGS+= -L.
CXXFLAGS+= -I.
#LIBS+= -lfoo

INCLUDE=$(wildcard *.h)
SRC=$(wildcard *.cpp)
OBJS=$(patsubst %.cpp,%.o,$(SRC))

SO=libassimp_anim_helper.so
LDFLAGS+= -shared -Wl,-soname,$(SO).1

all: $(SO)

$(SO): $(OBJS)
	$(CXX) -o $(SO) $(OBJS) $(LDFLAGS) $(LIBS)

$(OBJS): $(INCLUDE) $(SRC)

clean:
	$(RM) $(OBJS) $(SO)

.PHONY: all clean
