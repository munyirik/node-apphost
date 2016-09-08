//
// MainPage.xaml.cpp
// Implementation of the MainPage class.
//

#include "pch.h"
#include "MainPage.xaml.h"
#include <filesystem>
#include <ppltasks.h>
#include <sstream>

using namespace test_app_uwp;

using namespace Platform;
using namespace Platform::Collections;
using namespace Windows::Foundation;
using namespace Windows::Foundation::Collections;
using namespace Windows::Storage;
using namespace Windows::Storage::Search;
using namespace Windows::UI::Xaml;
using namespace Windows::UI::Xaml::Controls;
using namespace Windows::UI::Xaml::Controls::Primitives;
using namespace Windows::UI::Xaml::Data;
using namespace Windows::UI::Xaml::Input;
using namespace Windows::UI::Xaml::Media;
using namespace Windows::UI::Xaml::Navigation;
using namespace Windows::Data::Json;
using namespace std;
using namespace std::tr2::sys;
using namespace Windows::Data::Xml::Dom;
using namespace concurrency;

void test();

// The Blank Page item template is documented at http://go.microsoft.com/fwlink/?LinkId=402352&clcid=0x409

void MainPage::Run()
{
	StorageFolder^ appFolder = Windows::ApplicationModel::Package::Current->InstalledLocation;

	task<StorageFile^> getStartupInfo;
	getStartupInfo = create_task(appFolder->GetFileAsync(L"package.json"));

	getStartupInfo.then([=](StorageFile^ storageFile)
	{
		create_task(FileIO::ReadTextAsync(storageFile)).then([=](String^ jsonStr)
		{
			test();
		}, task_continuation_context::use_arbitrary());
	});

}

MainPage::MainPage()
{
	InitializeComponent();
	Run();
}
