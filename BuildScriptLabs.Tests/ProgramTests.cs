using System;
//using Microsoft.VisualStudio.TestTools.UnitTesting;
using Xunit;

namespace BuildScriptLabs.Tests
{

    public class ProgramTests
    {

        [Fact]
        public void Add_TwoNumbers_Success()
        {
            Program program = new Program();
            var result = program.Add(2, 3);
            Assert.Equal(5, result);
        }
    }
}
